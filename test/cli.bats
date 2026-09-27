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
  for cmd in diff init fetch merge pull prune push status; do
    run "$entrypoint" "$cmd" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: git subtrees $cmd"* ]]
  done
}

@test "cli: -- terminates options so a path named like a flag is treated literally" {
  init_monorepo "$monorepo"
  cd "$monorepo"

  for cmd in diff fetch pull push status; do
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

@test "cli: push --base runs through the real entrypoint" {
  hermetic_git_config
  load 'scenarios/feature-branch-unchanged/setup'
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  run "$entrypoint" push --base main
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to push"* ]]
}

@test "cli: top-level usage mentions --base for diff, push, and status" {
  run "$entrypoint" -h
  [[ "$output" == *"diff [--base <b>]"* ]]
  [[ "$output" == *"push [--base <b>]"* ]]
  [[ "$output" == *"status [--base <b>]"* ]]
}

@test "cli: every command refuses nested subtrees before doing anything" {
  load 'scenarios/nested-subtrees/setup'
  scenario_nested_subtrees "$monorepo" "$upstream"
  cd "$monorepo"
  local before cmd
  before="$(git rev-parse HEAD)"
  for cmd in status diff fetch merge pull push prune; do
    run "$entrypoint" "$cmd"
    [ "$status" -eq 1 ]
    [[ "$output" == *"nested subtrees are not supported: 'vendor/pkg' and 'vendor/pkg/extra' overlap"* ]]
  done
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ -z "$(git for-each-ref refs/remotes/vendor/pkg/extra/)" ]
}

@test "cli: a remote overlapping a subtree is refused even without a folder of its own" {
  load 'scenarios/nested-subtrees/setup'
  scenario_nested_subtrees "$monorepo" "$upstream"
  cd "$monorepo"
  git rm -q -r vendor/pkg/extra
  git commit -q -m "drop the inner folder, keep its remote"

  run "$entrypoint" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"nested subtrees are not supported: 'vendor/pkg' and 'vendor/pkg/extra' overlap"* ]]
}

@test "cli: removing the inner remote with the suggested commands leaves the outer subtree usable" {
  load 'scenarios/nested-subtrees/setup'
  scenario_nested_subtrees "$monorepo" "$upstream"
  cd "$monorepo"
  git fetch -q vendor/pkg/extra
  [ -n "$(git for-each-ref refs/remotes/vendor/pkg/extra/)" ]

  git remote remove vendor/pkg/extra
  git for-each-ref --format='delete %(refname)' refs/remotes/vendor/pkg/extra/ | git update-ref --no-deref --stdin

  [ -z "$(git for-each-ref refs/remotes/vendor/pkg/extra/)" ]
  run "$entrypoint" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/pkg -> $upstream"* ]]
}

@test "cli: the printed nested-subtree fix is safe to run for a name with shell metacharacters" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/pkg"
  cd "$monorepo"
  local inner='vendor/pkg/x;touch${IFS}pwned'
  git config "remote.$inner.url" "$upstream"

  run "$entrypoint" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"git remote remove 'vendor/pkg/x;touch\${IFS}pwned'"* ]]

  # Run the second suggested fix exactly as printed.
  printf '%s\n' "$output" | grep -A1 -F "git remote remove '" | sed 's/^  //' | bash
  [ ! -e pwned ]
  run git config --get "remote.$inner.url"
  [ "$status" -ne 0 ]
  run "$entrypoint" status
  [ "$status" -eq 0 ]
}

@test "cli: top-level help lists every command's --base option" {
  run "$entrypoint" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"diff [--base <b>]"* ]]
  [[ "$output" == *"init [--base <b>] <path> <url>"* ]]
  [[ "$output" == *"push [--base <b>]"* ]]
  [[ "$output" == *"status [--base <b>]"* ]]
}

# Copies the entrypoint and lib/ into <dir>, as a release tarball or a
# package would install them.
install_copy() {
  mkdir -p "$1"
  cp -R "$BATS_TEST_DIRNAME/../git-subtrees" "$BATS_TEST_DIRNAME/../lib" "$1/"
}

@test "cli: --version outside a clone prints the release version" {
  install_copy "$BATS_TEST_TMPDIR/install"
  local version
  version="$(sed -n 's/^VERSION=\([^ ]*\).*/\1/p' "$BATS_TEST_DIRNAME/../git-subtrees")"

  run "$BATS_TEST_TMPDIR/install/git-subtrees" --version
  [ "$status" -eq 0 ]
  [ "$output" = "git subtrees version $version" ]
}

@test "cli: --version in a clone describes the checked-out commit" {
  hermetic_git_config
  local clone="$BATS_TEST_TMPDIR/clone"
  install_copy "$clone"
  git -C "$clone" init -q
  git -C "$clone" add .
  git -C "$clone" -c user.name=t -c user.email=t@example.com commit -q -m release
  git -C "$clone" tag v9.9.9
  git -C "$clone" tag edge
  git -C "$clone" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m next

  run "$clone/git-subtrees" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "git subtrees version 9.9.9-1-g"* ]]
}

@test "cli: --version unpacked inside another repository ignores that repository's tags" {
  hermetic_git_config
  local outer="$BATS_TEST_TMPDIR/outer"
  git init -q "$outer"
  git -C "$outer" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m outer
  git -C "$outer" tag v9.9.9
  install_copy "$outer/vendor/git-subtrees"
  local version
  version="$(sed -n 's/^VERSION=\([^ ]*\).*/\1/p' "$BATS_TEST_DIRNAME/../git-subtrees")"

  run "$outer/vendor/git-subtrees/git-subtrees" --version
  [ "$status" -eq 0 ]
  [ "$output" = "git subtrees version $version" ]
}

@test "cli: VERSION carries the marker release-please bumps it by" {
  grep -qx 'VERSION=[0-9.]* # x-release-please-version' "$BATS_TEST_DIRNAME/../git-subtrees"
}
