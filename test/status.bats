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
  load 'scenarios/diverged-then-pulled/setup'
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

@test "status: local changes still pending after pulling a divergence report push" {
  scenario_diverged_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [[ "$output" == *"(push)"* ]]
  [[ "$output" == *"local.txt"* ]]
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
  [[ "$output" == *"ghost [no mapping]"* ]]
}

@test "status: does not print unmapped remote URL" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git remote add origin "https://user:token@example.com/repo.git"

  run cmd_status

  [[ "$output" == *"origin [no mapping]"* ]]
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

@test "status: a branch missing on the remote, unchanged since the base branch" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status --base main
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a"*"(no 'feature' branch on remote; unchanged since 'main')"* ]]
}

@test "status: a branch missing on the remote, changed since the base branch, with a diffstat" {
  hermetic_git_config
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status --base main
  [[ "$output" == *"changed since 'main' -- push would create it"* ]]
  [[ "$output" == *"file.txt"* ]]
}

@test "status: finds the base branch through init.defaultBranch" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git config init.defaultBranch main
  run cmd_status
  [[ "$output" == *"unchanged since 'main'"* ]]
}

@test "status: without a base branch it asks for --base" {
  hermetic_git_config
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [[ "$output" == *"monorepo base branch unknown -- pass --base <branch>"* ]]
}

@test "status: an empty --base is an error" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status --base=
  [ "$status" -eq 1 ]
  [[ "$output" == *"--base needs a branch name"* ]]
}

@test "status: marks a push-protected subtree, without a warning" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git remote set-url --push vendor/a "$PUSH_PROTECTED_URL"

  run cmd_status
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a [push-protected] (up to date)" ]
}

@test "status: marks a subtree that isn't push-protected, without nagging about it" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git config --unset remote.vendor/a.pushurl

  run cmd_status
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a [NOT push-protected] (up to date)" ]
}

@test "status: -h shows a command that push-protects a subtree" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git config --unset remote.vendor/a.pushurl

  local fix
  fix="$(usage_status | grep 'git remote set-url --push')"
  eval "${fix//<path>/vendor/a}"
  is_push_protected vendor/a
}

@test "status: shows a remote with its own push URL as not push-protected" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git remote set-url --push vendor/a "$upstream"

  run cmd_status
  [[ "$output" == *"vendor/a [NOT push-protected]"* ]]
}

@test "status: colors [NOT push-protected] red on a terminal" {
  command -v script >/dev/null || skip "needs script(1) for a terminal"
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git config --unset remote.vendor/a.pushurl

  run script -qec "$BATS_TEST_DIRNAME/../git-subtrees status" /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\e[31m[NOT push-protected]\e[m'* ]]
}

@test "status: doesn't color where git wouldn't color its own status" {
  command -v script >/dev/null || skip "needs script(1) for a terminal"
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git config --unset remote.vendor/a.pushurl

  run cmd_status
  [[ "$output" != *$'\e['* ]]

  git config color.status never
  run script -qec "$BATS_TEST_DIRNAME/../git-subtrees status" /dev/null
  [[ "$output" == *"[NOT push-protected]"* ]]
  [[ "$output" != *$'\e['* ]]
}
