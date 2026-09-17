setup() {
  load 'helpers/fixtures'
  load_lib
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "prune: dry-run reports stale remote-tracking refs without deleting them" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  seed_bare_repo "$upstream" "temporary" "temporary"
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p vendor/a
  git remote add vendor/a "$upstream"
  git fetch -q vendor/a
  git -C "$upstream" update-ref -d refs/heads/temporary

  run cmd_prune --dry-run vendor/a

  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a/temporary"* ]]
  run git show-ref --verify --quiet refs/remotes/vendor/a/temporary
  [ "$status" -eq 0 ]
}

@test "prune: run from inside a subtree directory discovers the same as from the root" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  seed_bare_repo "$upstream" "temporary" "temporary"
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p vendor/a
  git remote add vendor/a "$upstream"
  git fetch -q vendor/a
  git -C "$upstream" update-ref -d refs/heads/temporary
  cd vendor/a

  run cmd_prune --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a/temporary"* ]]
}

@test "prune: a remote named like a flag is pruned, not parsed as one" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  seed_bare_repo "$upstream" "temporary" "temporary"
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir -p -- -n
  git remote add -- -n "$upstream"
  git fetch -q -- -n
  git -C "$upstream" update-ref -d refs/heads/temporary

  run cmd_prune -- -n

  [ "$status" -eq 0 ]
  run git show-ref --verify --quiet refs/remotes/-n/temporary
  [ "$status" -eq 1 ]
}

@test "prune: delegates ref cleanup to git remote prune" {
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

  run cmd_prune vendor/a

  [ "$status" -eq 0 ]
  run git show-ref --verify --quiet refs/remotes/vendor/a/temporary
  [ "$status" -eq 1 ]
  run git show-ref --verify --quiet refs/tags/local-only
  [ "$status" -eq 1 ]
}
