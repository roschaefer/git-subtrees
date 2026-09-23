setup() {
  load 'helpers/fixtures'
  load_lib
  load 'scenarios/up-to-date/setup'
  load 'scenarios/push-ahead/setup'
  load 'scenarios/pull-ahead/setup'
  load 'scenarios/diverged-common-ancestor/setup'
  load 'scenarios/diverged-unrelated-history/setup'
  load 'scenarios/not-connected/setup'
  load 'scenarios/feature-branch-unchanged/setup'
  load 'scenarios/feature-branch-changed/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "discover_subtrees finds only remotes matching a directory" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p vendor/a
  git remote add vendor/a "$upstream"
  git remote add ghost "$upstream" # no matching dir

  discover_subtrees

  [[ " ${ALL_REMOTES[*]} " == *" vendor/a "* ]]
  [[ " ${ALL_REMOTES[*]} " == *" ghost "* ]]
  [[ " ${ALL_PATHS[*]} " == *" vendor/a "* ]]
  [[ " ${ALL_PATHS[*]} " != *" ghost "* ]]
}

@test "discover_subtrees finds nested sibling remotes" {
  make_bare_repo "$upstream"
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p packages/alpha packages/bravo packages/charlie
  git remote add packages/alpha "$upstream"
  git remote add packages/bravo "$upstream"
  git remote add packages/charlie "$upstream"

  discover_subtrees

  [[ " ${ALL_PATHS[*]} " == *" packages/alpha "* ]]
  [[ " ${ALL_PATHS[*]} " == *" packages/bravo "* ]]
  [[ " ${ALL_PATHS[*]} " == *" packages/charlie "* ]]
}

@test "discover_subtrees is empty with zero remotes" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  discover_subtrees
  [[ ${#ALL_REMOTES[@]} -eq 0 ]]
  [[ ${#ALL_PATHS[@]} -eq 0 ]]
}

@test "is_subtree_path is false for an unmatched directory and an unmatched remote" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p not-a-subtree
  discover_subtrees
  run is_subtree_path "not-a-subtree"
  [ "$status" -eq 1 ]
  run is_subtree_path "vendor/nonexistent"
  [ "$status" -eq 1 ]
}

@test "usable_with_git_subtree is false only for a name starting with '-'" {
  run usable_with_git_subtree "vendor/a"
  [ "$status" -eq 0 ]
  run usable_with_git_subtree "-n"
  [ "$status" -eq 1 ]
  run usable_with_git_subtree "--dry-run"
  [ "$status" -eq 1 ]
}

@test "classify_subtree: up-to-date" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  classify_subtree "vendor/a" "main"
  [ "$SUBTREE_STATE" = "up-to-date" ]
}

@test "classify_subtree: push" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  classify_subtree "vendor/a" "main"
  [ "$SUBTREE_STATE" = "push" ]
}

@test "classify_subtree: pull" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  classify_subtree "vendor/a" "main"
  [ "$SUBTREE_STATE" = "pull" ]
}

@test "classify_subtree: diverged (common ancestor)" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  classify_subtree "vendor/a" "main"
  [ "$SUBTREE_STATE" = "diverged" ]
}

@test "classify_subtree: unrelated-history (never subtree-added)" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p vendor/a
  echo "pre-existing" >vendor/a/other.txt
  git add vendor/a && git commit -q -m "pre-existing"
  git remote add vendor/a "$upstream"
  git fetch -q vendor/a
  classify_subtree "vendor/a" "main"
  [ "$SUBTREE_STATE" = "unrelated-history" ]
}

@test "classify_subtree: unrelated-history (remote history replaced after sync)" {
  scenario_diverged_unrelated_history "$monorepo" "$upstream"
  cd "$monorepo"
  classify_subtree "vendor/a" "main"
  [ "$SUBTREE_STATE" = "unrelated-history" ]
}

@test "classify_subtree: resolves the URL of a remote named like a flag" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p -- -n
  git remote add -- -n "$upstream"
  git fetch -q -- -n

  classify_subtree "-n" "main"
  [ "$SUBTREE_URL" = "$upstream" ]
}

@test "classify_subtree: not-connected" {
  scenario_not_connected "$monorepo" "$upstream"
  cd "$monorepo"
  classify_subtree "vendor/a" "main"
  [ "$SUBTREE_STATE" = "not-connected" ]
}

@test "classify_subtree: missing-at-head" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git remote add vendor/a "$upstream"
  git fetch -q vendor/a
  git checkout -q -b feature
  mkdir -p vendor/a
  classify_subtree "vendor/a" "feature"
  [ "$SUBTREE_STATE" = "missing-at-head" ]
}

@test "resolve_base_ref: prefers an explicit branch over the configured one" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git branch other main
  git config init.defaultBranch other
  run resolve_base_ref main
  [ "$status" -eq 0 ]
  [ "$output" = "refs/heads/main" ]
}

@test "resolve_base_ref: falls back to init.defaultBranch" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git config init.defaultBranch main
  run resolve_base_ref
  [ "$status" -eq 0 ]
  [ "$output" = "refs/heads/main" ]
}

# Gives the monorepo an "origin" of its own (not a subtree remote), with
# origin/HEAD pointing at main.
add_monorepo_origin() {
  local origin="$BATS_TEST_TMPDIR/monorepo-origin.git"
  make_bare_repo "$origin"
  git remote add origin "$origin"
  git push -q origin main
  git fetch -q origin
  git remote set-head origin main
}

@test "resolve_base_ref: uses origin/HEAD before init.defaultBranch" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git branch trunk main
  git config init.defaultBranch trunk
  add_monorepo_origin
  run resolve_base_ref
  [ "$status" -eq 0 ]
  [ "$output" = "refs/heads/main" ]
}

@test "resolve_base_ref: accepts origin/<name> when there is no local branch" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  add_monorepo_origin
  git branch -q -D main
  run resolve_base_ref
  [ "$status" -eq 0 ]
  [ "$output" = "refs/remotes/origin/main" ]
}

@test "resolve_base_ref: accepts a remote-tracking branch or a full ref as --base" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  add_monorepo_origin
  run resolve_base_ref origin/main
  [ "$status" -eq 0 ]
  [ "$output" = "refs/remotes/origin/main" ]
  run resolve_base_ref refs/heads/main
  [ "$status" -eq 0 ]
  [ "$output" = "refs/heads/main" ]
}

@test "resolve_base_ref: a stale local branch doesn't hide the fresher origin/<name>" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  add_monorepo_origin
  local stale
  stale="$(git rev-parse main)"
  git checkout -q main
  echo "changed on main" >>vendor/a/file.txt
  git commit -q -am "change on main"
  git push -q origin main
  git checkout -q -b fresh origin/main
  git branch -q -f main "$stale"
  git config init.defaultBranch main
  run resolve_base_ref
  [ "$status" -eq 0 ]
  [ "$output" = "refs/remotes/origin/main" ]
  changes_vs_base "vendor/a"
  [ "$SUBTREE_CHANGES_VS_BASE" = "no" ]
}

@test "resolve_base_ref: fails when nothing names a base branch" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  run resolve_base_ref
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "resolve_base_ref: fails for a branch that does not exist" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  run resolve_base_ref nope
  [ "$status" -eq 1 ]
}

@test "resolve_base_ref: rejects a branch that shares no history with HEAD" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git checkout -q --orphan orphan
  git commit -q --allow-empty -m "unrelated root"
  git checkout -q feature
  run resolve_base_ref orphan
  [ "$status" -eq 1 ]
}

@test "changes_vs_base: no when the subtree is untouched on this branch" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  changes_vs_base "vendor/a" main
  [ "$SUBTREE_CHANGES_VS_BASE" = "no" ]
  [ "$SUBTREE_BASE_BRANCH" = "main" ]
}

@test "changes_vs_base: yes when the subtree changed on this branch" {
  hermetic_git_config
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  changes_vs_base "vendor/a" main
  [ "$SUBTREE_CHANGES_VS_BASE" = "yes" ]
  [ "$SUBTREE_BASE_MERGE_BASE" = "$(git rev-parse main)" ]
}

@test "changes_vs_base: yes for a subtree added on this branch" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  local upstream_b="$BATS_TEST_TMPDIR/upstream-b.git"
  make_bare_repo "$upstream_b"
  seed_bare_repo "$upstream_b" "seed"
  add_subtree "$monorepo" "$upstream_b" "vendor/b"
  cd "$monorepo"
  changes_vs_base "vendor/b" main
  [ "$SUBTREE_CHANGES_VS_BASE" = "yes" ]
}

@test "changes_vs_base: changes made on the base branch after the cut don't count" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git checkout -q main
  echo "later, on main" >>vendor/a/file.txt
  git commit -q -am "change on main"
  git checkout -q feature
  changes_vs_base "vendor/a" main
  [ "$SUBTREE_CHANGES_VS_BASE" = "no" ]
}

@test "changes_vs_base: changes already on the base branch don't count" {
  hermetic_git_config
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git checkout -q -b feature
  changes_vs_base "vendor/a" main
  [ "$SUBTREE_CHANGES_VS_BASE" = "no" ]
}

@test "changes_vs_base: self on the base branch itself" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git checkout -q main
  changes_vs_base "vendor/a" main
  [ "$SUBTREE_CHANGES_VS_BASE" = "self" ]
}

@test "changes_vs_base: a git failure is reported as error, never as changed" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  changes_vs_base ":(bogus)vendor/a" main
  [ "$SUBTREE_CHANGES_VS_BASE" = "error" ]
}

@test "changes_vs_base: unresolved without a base branch" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  changes_vs_base "vendor/a"
  [ "$SUBTREE_CHANGES_VS_BASE" = "unresolved" ]
  [ -z "$SUBTREE_BASE_REF" ]
}

@test "shell_quote leaves plain words alone and quotes everything else as one word" {
  [ "$(shell_quote vendor/a)" = "vendor/a" ]
  [ "$(shell_quote 'x;id')" = "'x;id'" ]
  local quoted
  quoted="$(shell_quote "it's \$HOME")"
  [ "$(eval "printf '%s' $quoted")" = "it's \$HOME" ]
}

@test "print_unrelated_history_guidance quotes names with shell metacharacters" {
  run print_unrelated_history_guidance 'vendor/x;id' main
  [[ "$output" == *"git rm -r 'vendor/x;id'"* ]]
  [[ "$output" == *"git push --force 'vendor/x;id' 'tmp-split-x;id:main'"* ]]
}
