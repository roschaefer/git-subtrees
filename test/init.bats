setup() {
  load 'helpers/fixtures'
  load_lib
  load 'scenarios/init-unrelated-content/setup'
  load 'scenarios/init-on-feature-branch/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "init: refuses a path nested inside an existing subtree, without registering a remote" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/a"
  cd "$monorepo"

  run cmd_init "vendor/a/extra" "$upstream"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nested subtrees are not supported: 'vendor/a' and 'vendor/a/extra' overlap"* ]]
  run git remote get-url vendor/a/extra
  [ "$status" -ne 0 ]
}

@test "init: refuses a path containing an existing subtree, without registering a remote" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/a"
  cd "$monorepo"

  run cmd_init "vendor" "$upstream"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nested subtrees are not supported: 'vendor' and 'vendor/a' overlap"* ]]
  run git remote get-url vendor
  [ "$status" -ne 0 ]
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

@test "init: -- reaches a path named like a flag, but git-subtree still can't use it" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"

  run cmd_init -- -h "$upstream"

  [ "$status" -eq 1 ]
  [[ "$output" == *"git-subtree cannot use a name starting with '-'"* ]]
  run git remote get-url -- -h
  [ "$status" -eq 2 ]
}

@test "init: refuses when the current branch name starts with '-', without registering a remote" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git symbolic-ref HEAD refs/heads/-weird

  run cmd_init "vendor/a" "$upstream"

  [ "$status" -eq 1 ]
  [[ "$output" == *"git-subtree cannot use a branch name starting with '-'"* ]]
  run git remote get-url vendor/a
  [ "$status" -eq 2 ]
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

@test "init: fails on a genuine fetch failure, distinct from a missing branch" {
  init_monorepo "$monorepo"
  cd "$monorepo"

  run cmd_init "vendor/a" "$BATS_TEST_TMPDIR/missing.git"

  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: fetch failed"* ]]
  [[ "$output" != *"nothing to add"* ]]
}

@test "init: no-op when remote lacks the current branch and no base branch resolves" {
  hermetic_git_config
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git checkout -q -b feature

  run cmd_init "vendor/a" "$upstream"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to add (pass --base <branch>"* ]]
  [[ "$output" != *"fetch failed"* ]]
  [[ "$output" != *"couldn't find remote ref"* ]]
  [ ! -e vendor/a ]
}

@test "init: exact branch probe does not match branch-name suffixes" {
  hermetic_git_config
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "team feature" "team/feature"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git checkout -q -b feature

  run cmd_init "vendor/a" "$upstream"

  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to add"* ]]
  [[ "$output" != *"fetch failed"* ]]
  [[ "$output" != *"couldn't find remote ref"* ]]
}

@test "init: on a branch the remote lacks, adds the remote's base branch" {
  hermetic_git_config
  scenario_init_on_feature_branch "$monorepo" "$upstream"
  cd "$monorepo"

  run cmd_init "vendor/a" "$upstream"
  [ "$status" -eq 0 ]
  [[ "$output" == *"using its 'main' branch; your first push creates 'feature'"* ]]
  run grep -qx "seed" vendor/a/file.txt
  [ "$status" -eq 0 ]
  run git -C "$upstream" rev-parse --verify --quiet refs/heads/feature
  [ "$status" -ne 0 ]

  classify_subtree "vendor/a" "feature"
  [ "$SUBTREE_STATE" = "missing-at-head" ]
  changes_vs_base "vendor/a"
  [ "$SUBTREE_CHANGES_VS_BASE" = "yes" ]
}

@test "init: after adding from the base branch, the first push creates the branch on top of it" {
  hermetic_git_config
  scenario_init_on_feature_branch "$monorepo" "$upstream"
  cd "$monorepo"
  cmd_init "vendor/a" "$upstream"
  echo "feature change" >>vendor/a/file.txt
  git commit -q -am "feature change"

  run push_one "vendor/a" "feature"
  [ "$status" -eq 0 ]
  git -C "$upstream" merge-base --is-ancestor main feature
  run git -C "$upstream" show feature:file.txt
  [[ "$output" == *"feature change"* ]]
}

@test "init: --base names the base branch when nothing else resolves" {
  hermetic_git_config
  scenario_init_on_feature_branch "$monorepo" "$upstream"
  cd "$monorepo"
  git config --unset init.defaultBranch

  run cmd_init --base main "vendor/a" "$upstream"
  [ "$status" -eq 0 ]
  [[ "$output" == *"using its 'main' branch"* ]]
  [ -f vendor/a/file.txt ]
}

@test "init: only registers the remote when it lacks the base branch too" {
  hermetic_git_config
  make_bare_repo "$upstream"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git config init.defaultBranch main
  git checkout -q -b feature

  run cmd_init "vendor/a" "$upstream"
  [ "$status" -eq 0 ]
  [[ "$output" == *"remote has no 'feature' branch yet -- nothing to add"* ]]
  [ ! -e vendor/a ]
  run git remote get-url vendor/a
  [ "$output" = "$upstream" ]
}

@test "init: rejects more than one path/url pair" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  run cmd_init "vendor/a" "$upstream" "extra"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: git subtrees init"* ]]
}
