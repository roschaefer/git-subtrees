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

@test "discover_subtrees finds only remotes matching a directory" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p vendor/a
  git remote add vendor/a "$upstream"
  git remote add ghost "$upstream" # no matching dir

  discover_subtrees

  [[ " ${ALL_REMOTES[*]} " == *" vendor/a "* ]]
  [[ " ${ALL_REMOTES[*]} " == *" ghost "* ]]
  [[ " ${ALL_PATHS[*]} " == *" vendor/a "* ]]
  [[ " ${ALL_PATHS[*]} " != *" ghost "* ]]
}

@test "discover_subtrees is empty with zero remotes" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  discover_subtrees
  [[ ${#ALL_REMOTES[@]} -eq 0 ]]
  [[ ${#ALL_PATHS[@]} -eq 0 ]]
}

@test "is_subtree_path is false for an unmatched directory and an unmatched remote" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p not-a-subtree
  discover_subtrees
  run is_subtree_path "not-a-subtree"
  [ "$status" -eq 1 ]
  run is_subtree_path "vendor/nonexistent"
  [ "$status" -eq 1 ]
}

@test "classify_subtree: up-to-date" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  classify_subtree "vendor/a" "main"
  [ "$SUBTREE_STATE" = "up-to-date" ]
}

@test "classify_subtree: push" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  classify_subtree "vendor/a" "main"
  [ "$SUBTREE_STATE" = "push" ]
}

@test "classify_subtree: pull" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  classify_subtree "vendor/a" "main"
  [ "$SUBTREE_STATE" = "pull" ]
}

@test "classify_subtree: diverged (common ancestor)" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  classify_subtree "vendor/a" "main"
  [ "$SUBTREE_STATE" = "diverged" ]
}

@test "classify_subtree: unrelated-history (never subtree-added)" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p vendor/a
  echo "pre-existing" >vendor/a/other.txt
  git add vendor/a && git commit -q -m "pre-existing"
  git remote add vendor/a "$upstream"
  git fetch -q vendor/a
  classify_subtree "vendor/a" "main"
  [ "$SUBTREE_STATE" = "unrelated-history" ]
}

@test "classify_subtree: unrelated-history (remote history replaced after sync)" {
  scenario_diverged_unrelated_history "$monorepo" "$upstream"
  cd "$monorepo"
  classify_subtree "vendor/a" "main"
  [ "$SUBTREE_STATE" = "unrelated-history" ]
}

@test "classify_subtree: not-connected" {
  scenario_not_connected "$monorepo" "$upstream"
  cd "$monorepo"
  classify_subtree "vendor/a" "main"
  [ "$SUBTREE_STATE" = "not-connected" ]
}

@test "classify_subtree: missing-at-head" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git remote add vendor/a "$upstream"
  git fetch -q vendor/a
  git checkout -q -b feature
  mkdir -p vendor/a
  classify_subtree "vendor/a" "feature"
  [ "$SUBTREE_STATE" = "missing-at-head" ]
}
