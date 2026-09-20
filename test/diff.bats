setup() {
  load 'helpers/fixtures'
  load_lib
  load 'scenarios/up-to-date/setup'
  load 'scenarios/push-ahead/setup'
  load 'scenarios/pull-ahead/setup'
  load 'scenarios/feature-branch-unchanged/setup'
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

@test "diff: subtree added on this branch is compared against the empty tree" {
  hermetic_git_config
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  local upstream_b="$BATS_TEST_TMPDIR/upstream-b.git"
  make_bare_repo "$upstream_b"
  seed_bare_repo "$upstream_b" "seed-b"
  add_subtree "$monorepo" "$upstream_b" "vendor/b"
  cd "$monorepo"

  run cmd_diff --base main vendor/b

  [ "$status" -eq 0 ]
  [[ "$output" == *"new file mode"* ]]
  [[ "$output" == *"+seed-b"* ]]
}

@test "diff: path arguments restrict output" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"

  run cmd_diff vendor/a

  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a"* ]]
}

@test "diff: redirected output does not invoke the pager" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"

  run env GIT_PAGER=false "$BATS_TEST_DIRNAME/../git-subtrees" diff

  [ "$status" -eq 0 ]
  [[ "$output" == *"+local change"* ]]
  [[ "$output" != *$'\033['* ]]
}

@test "diff: output is colored while a pager is active" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"

  TERM=xterm run pipe_to_pager diff_paths cat main "" vendor/a

  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033['* ]]
}

@test "diff: quitting the pager early does not report a subtree failure" {
  diff_one() { return 141; }

  run diff_paths main "" vendor/a

  [ "$status" -eq 141 ]
  [[ "$output" != *"Failed:"* ]]
}

@test "diff: pager.subtrees=false overrides an exported pager" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git config pager.subtrees false

  GIT_PAGER='missing-pager' run subtrees_pager

  [ "$status" -eq 0 ]
  [ "$output" = cat ]
}

@test "diff: an empty pager.subtrees value disables paging" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git config pager.subtrees ""

  GIT_PAGER='missing-pager' run subtrees_pager

  [ "$status" -eq 0 ]
  [ "$output" = cat ]
}

@test "diff: a nonzero integer pager.subtrees value enables paging" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git config pager.subtrees 2

  GIT_PAGER='custom-pager' run subtrees_pager

  [ "$status" -eq 0 ]
  [ "$output" = custom-pager ]
}

@test "diff: git --no-pager overrides pager.subtrees" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git config pager.subtrees 'missing-pager'

  GIT_PAGER=cat run subtrees_pager

  [ "$status" -eq 0 ]
  [ "$output" = cat ]
}

@test "diff: pager startup failure is returned" {
  produce_diff() { printf 'patch\n'; }
  missing_pager_fails() {
    local rc=0
    pipe_to_pager produce_diff 'missing-pager-command' || rc=$?
    ((rc == 127))
  }

  run missing_pager_fails

  [ "$status" -eq 0 ]
}
