setup() {
  load 'helpers/fixtures'
  load_lib
  load 'scenarios/up-to-date/setup'
  load 'scenarios/push-ahead/setup'
  load 'scenarios/diverged-unrelated-history/setup'
  load 'scenarios/feature-branch-unchanged/setup'
  load 'scenarios/feature-branch-changed/setup'
  load 'scenarios/feature-branch-never-synced/setup'
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
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  run push_one "vendor/a" "feature"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to push"* ]]
  run remote_has_branch "$upstream" feature
  [ "$status" -ne 0 ]
}

@test "push: changed subtree on a branch the remote lacks creates that branch" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run push_one "vendor/a" "feature"
  [ "$status" -eq 0 ]
  [[ "$output" == *"this push will create it"* ]]

  local verify="$BATS_TEST_TMPDIR/verify"
  git clone -q -b feature "$upstream" "$verify" 2>/dev/null
  run grep -qx "local change" "$verify/file.txt"
  [ "$status" -eq 0 ]
}

@test "push: unchanged subtree is skipped even when the default branch moved on" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "upstream change"
  cd "$monorepo"
  git fetch -q vendor/a
  run push_one "vendor/a" "feature"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to push"* ]]
  run remote_has_branch "$upstream" feature
  [ "$status" -ne 0 ]
}

@test "push: never-synced subtree is refused, re-adopting from the default branch" {
  scenario_feature_branch_never_synced "$monorepo" "$upstream"
  cd "$monorepo"
  run push_one "vendor/a" "feature"
  [ "$status" -eq 1 ]
  [[ "$output" == *"git subtree add --prefix=vendor/a vendor/a main --squash"* ]]
  [[ "$output" == *"git push --force vendor/a"*":feature"* ]]
  run remote_has_branch "$upstream" feature
  [ "$status" -ne 0 ]
}

@test "push: refuses to create a branch when the remote lacks the default branch too" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed" other
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p vendor/a
  echo "content" >vendor/a/file.txt
  git add vendor/a && git commit -q -m "add vendor/a"
  git remote add vendor/a "$upstream"
  git fetch -q vendor/a
  git checkout -q -b feature
  run push_one "vendor/a" "feature"
  [ "$status" -eq 1 ]
  [[ "$output" == *"neither 'feature' nor the default branch 'main'"* ]]
  run remote_has_branch "$upstream" feature
  [ "$status" -ne 0 ]
}

@test "push: creates the default branch itself when the remote lacks it" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed" other
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p vendor/a
  echo "content" >vendor/a/file.txt
  git add vendor/a && git commit -q -m "add vendor/a"
  git remote add vendor/a "$upstream"
  git fetch -q vendor/a
  run push_one "vendor/a" "main"
  [ "$status" -eq 0 ]
  remote_has_branch "$upstream" main
}

@test "cmd_push: only creates the branch for the subtree that changed" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  local upstream_b="$BATS_TEST_TMPDIR/upstream-b.git"
  make_bare_repo "$upstream_b"
  seed_bare_repo "$upstream_b" "seed"
  git -C "$monorepo" checkout -q main
  add_subtree "$monorepo" "$upstream_b" "vendor/b"
  git -C "$monorepo" checkout -q feature
  git -C "$monorepo" merge -q --no-edit main
  cd "$monorepo"

  run cmd_push
  [ "$status" -eq 0 ]
  remote_has_branch "$upstream" feature
  run remote_has_branch "$upstream_b" feature
  [ "$status" -ne 0 ]
}
