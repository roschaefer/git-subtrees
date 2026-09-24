setup() {
  load 'helpers/fixtures'
  load_lib
  load 'scenarios/up-to-date/setup'
  load 'scenarios/push-ahead/setup'
  load 'scenarios/diverged-unrelated-history/setup'
  load 'scenarios/feature-branch-unchanged/setup'
  load 'scenarios/feature-branch-changed/setup'
  load 'scenarios/shared-remote-url/setup'
  load 'scenarios/pushed-then-changed/setup'
  load 'scenarios/diverged-then-pulled/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "push: pushes cleanly when local is ahead" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run push_one "vendor/a" "main"
  [ "$status" -eq 0 ]

  local verify="$BATS_TEST_TMPDIR/verify"
  git clone -q "$upstream" "$verify" 2>/dev/null
  run grep -qx "local change" "$verify/file.txt"
  [ "$status" -eq 0 ]
}

@test "push: no-op when up to date, never invokes git subtree push" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  local before after
  before="$(git -C "$upstream" rev-parse main)"
  run push_one "vendor/a" "main"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to push"* ]]
  after="$(git -C "$upstream" rev-parse main)"
  [ "$before" = "$after" ]
}

@test "push_one: refuses a path git-subtree cannot use, without attempting a push" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  classify_subtree() { SUBTREE_STATE="push"; SUBTREE_TARGET_REF="refs/heads/main"; }

  run push_one "-n" "main"

  [ "$status" -eq 1 ]
  [[ "$output" == *"git-subtree cannot use a name starting with '-'"* ]]
}

@test "push: unrelated-history does not attempt a push, prints guidance" {
  scenario_diverged_unrelated_history "$monorepo" "$upstream"
  cd "$monorepo"
  local before after
  before="$(git -C "$upstream" rev-parse main)"
  run push_one "vendor/a" "main"
  [ "$status" -eq 1 ]
  after="$(git -C "$upstream" rev-parse main)"
  [ "$before" = "$after" ]
  [[ "$output" == *"share no history"* ]]
  [[ "$output" == *"git push --force vendor/a"* ]]
}

@test "push_one: refuses a branch git-subtree cannot use, without classifying" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  classify_subtree() { echo "classify_subtree should not have been called" >&2; return 1; }

  run push_one "vendor/a" "-n"

  [ "$status" -eq 1 ]
  [[ "$output" == *"git-subtree cannot use a branch name starting with '-'"* ]]
}

remote_has_branch() {
  git -C "$1" rev-parse --verify --quiet "refs/heads/$2" >/dev/null
}

@test "push: unchanged subtree on a branch the remote lacks is skipped, no branch created" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  run push_one "vendor/a" "feature" "main"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to push"* ]]
  [[ "$output" == *"unchanged since 'main'"* ]]
  run remote_has_branch "$upstream" feature
  [ "$status" -ne 0 ]
}

@test "push: changed subtree on a branch the remote lacks creates that branch" {
  hermetic_git_config
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run push_one "vendor/a" "feature" "main"
  [ "$status" -eq 0 ]
  [[ "$output" == *"this push will create it"* ]]

  local verify="$BATS_TEST_TMPDIR/verify"
  git clone -q -b feature "$upstream" "$verify" 2>/dev/null
  run grep -qx "local change" "$verify/file.txt"
  [ "$status" -eq 0 ]
}

@test "push: finds the base branch through init.defaultBranch" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git config init.defaultBranch main
  run push_one "vendor/a" "feature"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unchanged since 'main'"* ]]
}

@test "push: without a base branch it refuses and asks for --base" {
  hermetic_git_config
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run push_one "vendor/a" "feature"
  [ "$status" -eq 1 ]
  [[ "$output" == *"re-run with --base <branch>"* ]]
  run remote_has_branch "$upstream" feature
  [ "$status" -ne 0 ]
}

@test "push: an unknown --base branch is reported as such" {
  hermetic_git_config
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run push_one "vendor/a" "feature" "nope"
  [ "$status" -eq 1 ]
  [[ "$output" == *"base branch 'nope' not found"* ]]
  run remote_has_branch "$upstream" feature
  [ "$status" -ne 0 ]
}

@test "push: unchanged subtree is skipped even after the base branch moved on" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git checkout -q main
  echo "later, on main" >>vendor/a/file.txt
  git commit -q -am "change on main"
  git checkout -q feature
  run push_one "vendor/a" "feature" "main"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to push"* ]]
  run remote_has_branch "$upstream" feature
  [ "$status" -ne 0 ]
}

@test "push: on the base branch itself, a missing remote branch is created" {
  hermetic_git_config
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed" other
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p vendor/a
  echo "content" >vendor/a/file.txt
  git add vendor/a && git commit -q -m "add vendor/a"
  git remote add vendor/a "$upstream"
  git fetch -q vendor/a
  run push_one "vendor/a" "main" "main"
  [ "$status" -eq 0 ]
  remote_has_branch "$upstream" main
}

@test "cmd_push: --base creates the branch only for the subtree that changed" {
  hermetic_git_config
  scenario_feature_branch_changed "$monorepo" "$upstream"
  local upstream_b="$BATS_TEST_TMPDIR/upstream-b.git"
  make_bare_repo "$upstream_b"
  seed_bare_repo "$upstream_b" "seed"
  git -C "$monorepo" checkout -q main
  add_subtree "$monorepo" "$upstream_b" "vendor/b"
  git -C "$monorepo" checkout -q feature
  git -C "$monorepo" merge -q --no-edit main
  cd "$monorepo"

  run cmd_push --base main
  [ "$status" -eq 0 ]
  remote_has_branch "$upstream" feature
  run remote_has_branch "$upstream_b" feature
  [ "$status" -ne 0 ]
}

@test "cmd_push: --base=<branch> and a path terminator both work" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push --base=main -- vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to push"* ]]
}

@test "cmd_push: --base without a value is an error" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push --base
  [ "$status" -eq 1 ]
  [[ "$output" == *"--base needs a branch name"* ]]
}

@test "cmd_push: without a resolvable base branch nothing is pushed and it exits 1" {
  hermetic_git_config
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push
  [ "$status" -eq 1 ]
  [[ "$output" == *"--base <branch>"* ]]
  run remote_has_branch "$upstream" feature
  [ "$status" -ne 0 ]
}

@test "cmd_push: an empty --base is an error, not 'no --base'" {
  hermetic_git_config
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  git config init.defaultBranch main
  run cmd_push --base=
  [ "$status" -eq 1 ]
  [[ "$output" == *"--base needs a branch name"* ]]
  run cmd_push --base ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"--base needs a branch name"* ]]
  run remote_has_branch "$upstream" feature
  [ "$status" -ne 0 ]
}

@test "push: two subtrees sharing a remote URL -- the second push is rejected, not overwritten" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  echo "a change" >>vendor/a/file.txt
  echo "b change" >vendor/b/new.txt
  git add vendor/a vendor/b
  git commit -q -m "change both"

  run push_one "vendor/a" "main"
  [ "$status" -eq 0 ]
  run push_one "vendor/b" "main"
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/b: push failed"* ]]
  [[ "$output" == *"(non-fast-forward)"* ]]

  local verify="$BATS_TEST_TMPDIR/verify"
  git clone -q "$upstream" "$verify" 2>/dev/null
  run grep -qx "a change" "$verify/file.txt"
  [ "$status" -eq 0 ]
  [ ! -e "$verify/new.txt" ]
}

@test "push: sends local changes that predate a pull of a divergence" {
  scenario_diverged_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  run push_one "vendor/a" "main"
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: pushed"* ]]

  local verify="$BATS_TEST_TMPDIR/verify"
  git clone -q "$upstream" "$verify" 2>/dev/null
  [ -f "$verify/local.txt" ]
  [ -f "$verify/upstream.txt" ]
}

@test "push: after our own push and another local change, pushes again as a fast-forward" {
  scenario_pushed_then_changed "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git -C "$upstream" rev-parse main)"

  run push_one "vendor/a" "main"
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: pushed"* ]]
  git -C "$upstream" merge-base --is-ancestor "$before" main
  run git -C "$upstream" show main:file.txt
  [[ "$output" == *"later change"* ]]
}
