setup() {
  load 'helpers/fixtures'
  load_lib
  load 'scenarios/up-to-date/setup'
  load 'scenarios/pull-ahead/setup'
  load 'scenarios/diverged-common-ancestor/setup'
  load 'scenarios/diverged-unrelated-history/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "pull: pulls cleanly when remote is ahead" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run pull_one "vendor/a" "main"
  [ "$status" -eq 0 ]
  run grep -qx "upstream change" vendor/a/file.txt
  [ "$status" -eq 0 ]
}

@test "pull: no-op when already up to date" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run pull_one "vendor/a" "main"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to pull"* ]]
}

@test "pull: ordinary conflict leaves MERGE_HEAD, resolved via plain git commit" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  run pull_one "vendor/a" "main"
  [ "$status" -eq 1 ]
  [ -f .git/MERGE_HEAD ]

  git add vendor/a/file.txt
  git commit -q --no-edit
  [ ! -f .git/MERGE_HEAD ]
}

@test "pull: unrelated-history does not attempt a merge, prints guidance" {
  scenario_diverged_unrelated_history "$monorepo" "$upstream"
  cd "$monorepo"
  run pull_one "vendor/a" "main"
  [ "$status" -eq 1 ]
  [ ! -f .git/MERGE_HEAD ]
  [[ "$output" == *"share no history"* ]]
  [[ "$output" == *"git subtree add --prefix=vendor/a"* ]]
}
