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

@test "fetch: reports when the matching remote branch moved despite an ambiguous short name" {
  local changed="$BATS_TEST_TMPDIR/changed.git" unchanged="$BATS_TEST_TMPDIR/unchanged.git"
  make_bare_repo "$changed"
  make_bare_repo "$unchanged"
  seed_bare_repo "$changed" "changed-seed"
  seed_bare_repo "$unchanged" "unchanged-seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p changed unchanged
  git remote add changed "$changed"
  git remote add unchanged "$unchanged"
  git fetch -q changed
  git fetch -q unchanged
  git tag main
  local old_sha
  old_sha="$(git rev-parse refs/remotes/changed/main)"
  seed_bare_repo "$changed" "remote-change"
  local new_sha
  new_sha="$(git --git-dir="$changed" rev-parse refs/heads/main)"

  run cmd_fetch

  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   changed fetched (main moved ${old_sha:0:7}..${new_sha:0:7})"* ]]
  [[ "$output" == *"ok   unchanged fetched"* ]]
  [[ "$output" != *"unchanged fetched ("* ]]
}

@test "fetch: a subtree remote named like a flag is fetched, not parsed as one" {
  local upstream="$BATS_TEST_TMPDIR/upstream.git"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p -- -n
  git remote add -- -n "$upstream"

  run cmd_fetch -- -n
  [ "$status" -eq 0 ]
  run git show-ref --verify --quiet refs/remotes/-n/main
  [ "$status" -eq 0 ]
}

@test "fetch: does not prune stale refs or local tags" {
  local upstream="$BATS_TEST_TMPDIR/upstream.git"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  seed_bare_repo "$upstream" "temporary" "temporary"
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p vendor/a
  git remote add vendor/a "$upstream"
  git fetch -q vendor/a
  git tag local-only
  git config --add remote.vendor/a.fetch "+refs/tags/*:refs/tags/*"
  git -C "$upstream" update-ref -d refs/heads/temporary

  run cmd_fetch

  [ "$status" -eq 0 ]
  run git show-ref --verify --quiet refs/remotes/vendor/a/temporary
  [ "$status" -eq 0 ]
  run git show-ref --verify --quiet refs/tags/local-only
  [ "$status" -eq 0 ]
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

@test "fetch_one preserves diagnostics for branch fetch failures" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git remote add vendor/a "$BATS_TEST_TMPDIR/missing.git"

  run fetch_one vendor/a main

  [ "$status" -eq 1 ]
  [[ "$output" == *"does not appear to be a git repository"* ]]
  [[ "$output" == *"vendor/a fetch failed"* ]]
}

@test "fetch_all_parallel treats --quiet as a path" {
  fetch_one() { log_ok "$1 fetched"; }

  fetch_all_parallel --quiet

  [[ ${#FETCH_PATHS[@]} -eq 1 ]]
  [[ "${FETCH_PATHS[0]}" == "--quiet" ]]
  [[ "${FETCH_OUTPUT[0]}" == "ok   --quiet fetched" ]]
}

@test "fetch_all_parallel_for_branch passes explicit branch to fetch_one" {
  fetch_one() { log_ok "$1:$2 fetched"; }

  fetch_all_parallel_for_branch feature vendor/a

  [[ "${FETCH_OUTPUT[0]}" == "ok   vendor/a:feature fetched" ]]
}
