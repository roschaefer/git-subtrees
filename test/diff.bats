setup() {
  load 'helpers/fixtures'
  load_lib
  load 'scenarios/up-to-date/setup'
  load 'scenarios/push-ahead/setup'
  load 'scenarios/pull-ahead/setup'
  load 'scenarios/feature-branch-changed/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "diff: shows the patch that would be pushed" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"

  run cmd_diff

  [ "$status" -eq 0 ]
  [[ "$output" == *"===  vendor/a"* ]]
  [[ "$output" == *"diff --git a/file.txt b/file.txt"* ]]
  [[ "$output" == *"+local"* ]]
}

@test "diff: prints nothing for a subtree with nothing to push" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"

  run cmd_diff

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "diff: does not show remote-only changes" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"

  run cmd_diff

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "diff: missing remote branch compares against the monorepo base" {
  hermetic_git_config
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"

  run cmd_diff --base main

  [ "$status" -eq 0 ]
  [[ "$output" == *"diff --git a/file.txt b/file.txt"* ]]
  [[ "$output" == *"+local change"* ]]
}

@test "diff: path arguments restrict output" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"

  run cmd_diff vendor/a

  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a"* ]]
}
