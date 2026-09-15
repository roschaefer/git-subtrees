setup() {
  load 'helpers/fixtures'
  load_lib
  load 'scenarios/init-unrelated-content/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "init: adds a fresh empty path" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"

  run cmd_init "vendor/a" "$upstream"
  [ "$status" -eq 0 ]
  [ -f vendor/a/file.txt ]
  run git remote get-url vendor/a
  [ "$output" = "$upstream" ]
}

@test "init: refuses when remote exists pointing elsewhere" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git remote add vendor/a "/some/other/url"

  run cmd_init "vendor/a" "$upstream"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already registered"* ]]
}

@test "init: no-op when already initialized" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/a"
  cd "$monorepo"

  run cmd_init "vendor/a" "$upstream"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already initialized"* ]]
}

@test "init: refuses unrelated pre-existing content with move-aside guidance" {
  scenario_init_unrelated_content "$monorepo" "$upstream"
  cd "$monorepo"

  run cmd_init "vendor/a" "$upstream"
  [ "$status" -eq 1 ]
  [[ "$output" == *"move it aside"* ]]
  [[ "$output" == *"mv vendor/a vendor/a.bak"* ]]
}

@test "init: no-op when remote has no matching branch yet" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git checkout -q -b feature

  run cmd_init "vendor/a" "$upstream"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to add"* ]]
}
