setup() {
  load 'helpers/fixtures'
  load_lib
  load 'scenarios/up-to-date/setup'
  load 'scenarios/pull-ahead/setup'
  load 'scenarios/not-connected/setup'
  load 'scenarios/diverged-common-ancestor/setup'
  load 'scenarios/diverged-unrelated-history/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "merge: merges already-fetched changes when the remote is ahead" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_merge vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: merged"* ]]
  run grep -qx "upstream change" vendor/a/file.txt
  [ "$status" -eq 0 ]
}

@test "merge: never contacts the remote, so unfetched upstream changes are not merged" {
  scenario_up_to_date "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "not fetched yet"
  cd "$monorepo"
  run cmd_merge vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to merge"* ]]
  run grep -qx "not fetched yet" vendor/a/file.txt
  [ "$status" -eq 1 ]
}

@test "merge: no-op when already up to date" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_merge
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: nothing to merge"* ]]
}

@test "merge: a never-fetched remote fails and points at fetch" {
  scenario_not_connected "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_merge vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"not fetched yet -- run 'git subtrees fetch' first"* ]]
  [[ "$output" == *"Failed: vendor/a"* ]]
}

@test "merge: ordinary conflict leaves MERGE_HEAD, resolved via plain git commit" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_merge vendor/a
  [ "$status" -eq 1 ]
  [ -f .git/MERGE_HEAD ]
  [[ "$output" == *"merge failed"* ]]

  git add vendor/a/file.txt
  git commit -q --no-edit
  [ ! -f .git/MERGE_HEAD ]
}

@test "merge: unrelated-history does not attempt a merge, prints guidance" {
  scenario_diverged_unrelated_history "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_merge vendor/a
  [ "$status" -eq 1 ]
  [ ! -f .git/MERGE_HEAD ]
  [[ "$output" == *"share no history"* ]]
}

@test "merge: rejects a path that is not a subtree" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_merge nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a subtree path: nope"* ]]
}

@test "merge_one: refuses a branch git-subtree cannot use" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  run merge_one "vendor/a" "-n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"git-subtree cannot use a branch name starting with '-'"* ]]
}

@test "merge: never fetches a missing split object, reports it instead" {
  local monorepo_origin="$BATS_TEST_TMPDIR/monorepo-origin.git"
  local fresh_monorepo="$BATS_TEST_TMPDIR/fresh-monorepo"
  local rewrite="$BATS_TEST_TMPDIR/rewrite"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/a"
  # --no-local: a local clone would hardlink the whole object store,
  # including the now-unreachable split commit we need to be missing.
  git clone -q --no-local --bare "$monorepo" "$monorepo_origin"
  git clone -q --no-local "$monorepo_origin" "$fresh_monorepo"
  (
    git clone -q "$upstream" "$rewrite"
    cd "$rewrite"
    git config user.name "Test"
    git config user.email "test@example.com"
    git checkout -q --orphan unrelated-main
    rm -f file.txt
    echo "brand new unrelated history" >file.txt
    git add file.txt
    git commit -q -m "brand new unrelated history"
    git push -q --force origin HEAD:main
  )
  cd "$fresh_monorepo"
  git config user.name "Test"
  git config user.email "test@example.com"
  git remote add vendor/a "$upstream"
  git fetch -q vendor/a "+refs/heads/main:refs/remotes/vendor/a/main"
  # The remote is gone: any attempt to reach it would fail loudly.
  git remote set-url vendor/a "$BATS_TEST_TMPDIR/does-not-exist.git"

  run cmd_merge vendor/a

  [ "$status" -eq 1 ]
  [[ "$output" == *"is not available locally"* ]]
  [[ "$output" == *"git subtrees pull vendor/a"* ]]
  [ ! -f .git/MERGE_HEAD ]
}

@test "merge: stops after a conflict instead of failing the remaining subtrees" {
  local upstream_b="$BATS_TEST_TMPDIR/upstream-b.git"
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  make_bare_repo "$upstream_b"
  seed_bare_repo "$upstream_b" "seed"
  add_subtree "$monorepo" "$upstream_b" "vendor/b"
  seed_bare_repo "$upstream_b" "upstream change"
  cd "$monorepo"
  git fetch -q vendor/b

  run cmd_merge vendor/a vendor/b

  [ "$status" -eq 1 ]
  [ -f .git/MERGE_HEAD ]
  [[ "$output" == *"Failed: vendor/a"* ]]
  [[ "$output" == *"Not merged: vendor/b"* ]]
  [[ "$output" != *"working tree has modifications"* ]]
  run grep -qx "upstream change" vendor/b/file.txt
  [ "$status" -eq 1 ]
}
