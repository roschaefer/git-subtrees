setup() {
  load 'helpers/fixtures'
  load_lib
  load 'scenarios/up-to-date/setup'
  load 'scenarios/push-ahead/setup'
  load 'scenarios/diverged-unrelated-history/setup'
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

@test "push_one: refuses a path git-subtree cannot use, without attempting a push" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  classify_subtree() { SUBTREE_STATE="push"; SUBTREE_TARGET_REF="refs/heads/main"; }

  run push_one "-n" "main"

  [ "$status" -eq 1 ]
  [[ "$output" == *"git-subtree cannot use a name starting with '-'"* ]]
}

@test "push_one: refuses a branch git-subtree cannot use, without classifying" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  classify_subtree() { echo "classify_subtree should not have been called" >&2; return 1; }

  run push_one "vendor/a" "-n"

  [ "$status" -eq 1 ]
  [[ "$output" == *"git-subtree cannot use a branch name starting with '-'"* ]]
}
