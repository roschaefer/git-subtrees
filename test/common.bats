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
  load 'scenarios/feature-branch-never-synced/setup'
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

@test "find_merge_commit_for_sync is safe with pipefail after later history" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  local i
  for i in $(seq 1 200); do
    git commit -q --allow-empty -m "later $i"
  done
  local sync_commit
  sync_commit="$(find_sync_commit vendor/a)"

  run bash -c 'set -euo pipefail; source "$1"; find_merge_commit_for_sync "$2"' \
    _ "$BATS_TEST_DIRNAME/../lib/common.sh" "$sync_commit"

  [ "$status" -eq 0 ]
  [[ -n "$output" ]]
  [[ "$(git rev-list --count "$sync_commit..HEAD")" -lt "$(git rev-list --count HEAD)" ]]
}

@test "find_merge_commit_for_sync bounds its walk to the sync commit's ancestry path" {
  # The pre-sync commits below are reachable from HEAD only through the
  # merge commit's *other* parent, not from sync_commit -- so a plain
  # "sync_commit..HEAD" range (without --ancestry-path) still includes them,
  # even though they aren't on the path we actually care about.
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  local i
  for i in $(seq 1 200); do
    git commit -q --allow-empty -m "earlier $i"
  done
  add_subtree "$monorepo" "$upstream" "vendor/a"
  local sync_commit merge_commit git_rev_list_log
  sync_commit="$(find_sync_commit vendor/a)"
  git_rev_list_log="$BATS_TEST_TMPDIR/git-rev-list.log"

  # Shadow `git` to capture the exact rev-list invocation
  # find_merge_commit_for_sync makes, without changing its behavior.
  git() {
    if [[ "$1" == "rev-list" ]]; then
      printf '%s\n' "$*" >>"$git_rev_list_log"
    fi
    command git "$@"
  }

  merge_commit="$(find_merge_commit_for_sync "$sync_commit")"

  [[ "$merge_commit" == "$(command git rev-parse HEAD)" ]]
  grep -qx -- "rev-list --ancestry-path $sync_commit..HEAD --parents" "$git_rev_list_log"
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

@test "classify_subtree: missing-at-head, no local changes" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  classify_subtree "vendor/a" "feature"
  [ "$SUBTREE_STATE" = "missing-at-head" ]
  [ "$SUBTREE_LOCAL_CHANGES" = "no" ]
}

@test "classify_subtree: missing-at-head, local changes" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  classify_subtree "vendor/a" "feature"
  [ "$SUBTREE_STATE" = "missing-at-head" ]
  [ "$SUBTREE_LOCAL_CHANGES" = "yes" ]
}

@test "classify_subtree: missing-at-head, local changes unknown (never synced)" {
  scenario_feature_branch_never_synced "$monorepo" "$upstream"
  cd "$monorepo"
  classify_subtree "vendor/a" "feature"
  [ "$SUBTREE_STATE" = "missing-at-head" ]
  [ "$SUBTREE_LOCAL_CHANGES" = "unknown" ]
}

@test "classify_subtree: missing-at-head, local changes unknown for a non-squash subtree" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git remote add vendor/a "$upstream"
  git fetch -q vendor/a
  git subtree add -q --prefix=vendor/a vendor/a main
  git checkout -q -b feature
  echo "local change" >>vendor/a/file.txt
  git commit -q -am "local change"
  classify_subtree "vendor/a" "feature"
  [ "$SUBTREE_STATE" = "missing-at-head" ]
  [ "$SUBTREE_LOCAL_CHANGES" = "unknown" ]
}

@test "classify_subtree: SUBTREE_LOCAL_CHANGES stays empty unless missing-at-head" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  classify_subtree "vendor/a" "main"
  [ -z "$SUBTREE_LOCAL_CHANGES" ]
}
