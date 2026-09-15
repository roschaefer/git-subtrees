setup() {
  load 'helpers/fixtures'
  load_lib
  monorepo="$BATS_TEST_TMPDIR/monorepo"
}

@test "fetch: updates tracking refs, leaves FETCH_HEAD untouched" {
  local upstream="$BATS_TEST_TMPDIR/upstream.git"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p vendor/a
  git remote add vendor/a "$upstream"

  run cmd_fetch
  [ "$status" -eq 0 ]
  run git show-ref --verify --quiet refs/remotes/vendor/a/main
  [ "$status" -eq 0 ]
  [ ! -f .git/FETCH_HEAD ]
}

@test "fetch: one remote failing does not abort the others, exit reflects the failure" {
  local up_a="$BATS_TEST_TMPDIR/up-a.git" up_b="$BATS_TEST_TMPDIR/up-b.git"
  make_bare_repo "$up_a"
  seed_bare_repo "$up_a" "seed-a"
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p vendor/a vendor/b
  git remote add vendor/a "$up_a"
  git remote add vendor/b "$up_b" # never created -- fetch will fail

  run cmd_fetch
  [ "$status" -eq 1 ]
  local fetch_output="$output"
  run git show-ref --verify --quiet refs/remotes/vendor/a/main
  [ "$status" -eq 0 ]
  [[ "$fetch_output" == *"Failed: vendor/b"* ]]
}
