# Unlike the other *.bats files, these run the real entrypoint as a
# subprocess (never sourced functions) -- the only layer that would catch
# the symlink/`readlink -f`/`source=` wiring bug class described in
# lib/common.sh and git-subtrees.

setup() {
  load 'helpers/fixtures'
  entrypoint="$BATS_TEST_DIRNAME/../git-subtrees"
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "cli: no args prints usage to stderr and exits 1" {
  run "$entrypoint"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: git subtrees"* ]]
}

@test "cli: -h prints usage and exits 0" {
  run "$entrypoint" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: git subtrees"* ]]
}

@test "cli: unknown command errors and exits 1" {
  run "$entrypoint" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown command: bogus"* ]]
}

@test "cli: each subcommand's own -h works" {
  for cmd in init fetch pull prune push status; do
    run "$entrypoint" "$cmd" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: git subtrees $cmd"* ]]
  done
}

@test "cli: -- terminates options so a path named like a flag is treated literally" {
  init_monorepo "$monorepo"
  cd "$monorepo"

  for cmd in fetch pull push status; do
    run "$entrypoint" "$cmd" -- -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a subtree path: -h"* ]]
  done
}

@test "cli: full command set works when invoked through a symlink, as the real install does" {
  local bindir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bindir"
  ln -s "$entrypoint" "$bindir/git-subtrees"

  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"

  run "$bindir/git-subtrees" init vendor/a "$upstream"
  [ "$status" -eq 0 ]

  run "$bindir/git-subtrees" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"(up to date)"* ]]

  run "$bindir/git-subtrees" fetch
  [ "$status" -eq 0 ]

  echo "local" >>vendor/a/file.txt
  git add vendor/a/file.txt
  git commit -q -m "local"

  run "$bindir/git-subtrees" push
  [ "$status" -eq 0 ]
}
