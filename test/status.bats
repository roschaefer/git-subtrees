setup() {
  load 'helpers/fixtures'
  load_lib
  load 'scenarios/up-to-date/setup'
  load 'scenarios/push-ahead/setup'
  load 'scenarios/pull-ahead/setup'
  load 'scenarios/diverged-common-ancestor/setup'
  load 'scenarios/diverged-unrelated-history/setup'
  load 'scenarios/not-connected/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "status: reports up-to-date" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a"*"(up to date)"* ]]
}

@test "status: reports push" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [[ "$output" == *"(push)"* ]]
}

@test "status: reports pull" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [[ "$output" == *"(pull)"* ]]
}

@test "status: reports diverged with a diffstat" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [[ "$output" == *"(diverged)"* ]]
  [[ "$output" == *"file.txt"*"changed"* ]]
}

@test "status: reports unrelated-history distinctly from diverged" {
  scenario_diverged_unrelated_history "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [[ "$output" == *"unrelated history"* ]]
  [[ "$output" != *"(diverged)"* ]]
}

@test "status: reports not-connected" {
  scenario_not_connected "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [[ "$output" == *"never fetched"* ]]
}

@test "status: shows no mapping for a remote with no matching directory" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git remote add ghost "$upstream"
  run cmd_status
  [[ "$output" == *"ghost -> (no mapping)"* ]]
}

@test "status: path arguments restrict output to those paths" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  connect_subtree "$monorepo" "$upstream" "vendor/a"
  local upstream_b="$BATS_TEST_TMPDIR/upstream-b.git"
  make_bare_repo "$upstream_b"
  seed_bare_repo "$upstream_b" "seed-b"
  connect_subtree "$monorepo" "$upstream_b" "vendor/b"
  cd "$monorepo"

  run cmd_status vendor/a
  [[ "$output" == *"vendor/a"* ]]
  [[ "$output" != *"vendor/b"* ]]
}
