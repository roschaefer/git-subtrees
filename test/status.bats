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

@test "status: reports not-connected on stdout" {
  scenario_not_connected "$monorepo" "$upstream"
  cd "$monorepo"
  local stderr="$BATS_TEST_TMPDIR/status.stderr"

  run bash -c '"$1" status 2>"$2"' _ "$BATS_TEST_DIRNAME/../git-subtrees" "$stderr"

  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a"* ]]
  [[ "$output" == *"never fetched"* ]]
  [[ ! -s "$stderr" ]]
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

@test "status: does not print unmapped remote URL" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git remote add origin "https://user:token@example.com/repo.git"

  run cmd_status

  [[ "$output" == *"origin -> (no mapping)"* ]]
  [[ "$output" != *"token"* ]]
  [[ "$output" != *"example.com"* ]]
}

@test "status: path arguments restrict output to those paths" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/a"
  local upstream_b="$BATS_TEST_TMPDIR/upstream-b.git"
  make_bare_repo "$upstream_b"
  seed_bare_repo "$upstream_b" "seed-b"
  add_subtree "$monorepo" "$upstream_b" "vendor/b"
  local unmapped="$BATS_TEST_TMPDIR/unmapped.git"
  make_bare_repo "$unmapped"
  cd "$monorepo"
  git remote add ghost "$unmapped"

  run cmd_status vendor/a
  [[ "$output" == *"vendor/a"* ]]
  [[ "$output" != *"vendor/b"* ]]
  [[ "$output" != *"ghost"* ]]
}

@test "status: run from inside a subtree directory reports the same as from the root" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo/vendor/a"
  run cmd_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a"*"(up to date)"* ]]
  [[ "$output" != *"no mapping"* ]]
}

@test "status: a branch missing on the remote is reported against the default branch (up to date)" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a"*"(up to date vs default branch 'main')"* ]]
}

@test "status: a branch missing on the remote is reported against the default branch (push)" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [[ "$output" == *"vendor/a"*"(push vs default branch 'main')"* ]]
}

@test "status: warns when the remote has neither the branch nor the default branch" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed" other
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p vendor/a
  git remote add vendor/a "$upstream"
  git fetch -q vendor/a
  git checkout -q -b feature
  run cmd_status
  [[ "$output" == *"neither 'feature' nor default branch 'main'"* ]]
}
