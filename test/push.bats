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
