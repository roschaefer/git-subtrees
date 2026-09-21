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
