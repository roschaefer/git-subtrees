# Covers the completions for all three shells. bash's completion function is
# called directly, the way bash calls it; zsh and fish run the real shell.
# The zsh and fish tests skip when that shell isn't installed (the compat
# matrix only has bash); `nix develop` provides both.

setup() {
  load 'helpers/fixtures'
  # shellcheck disable=SC1091
  source "$BATS_TEST_DIRNAME/../completions/git-subtrees.bash"
  init_monorepo "$BATS_TEST_TMPDIR/monorepo"
  cd "$BATS_TEST_TMPDIR/monorepo"
  mkdir -p vendor/a
  git remote add vendor/a "$BATS_TEST_TMPDIR/unused.git"
}

# Completes the words given as arguments; the last one is the word under the
# cursor. Prints one candidate per line.
complete_words() {
  COMP_WORDS=("$@")
  COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
  COMPREPLY=()
  _git_subtrees
  printf '%s\n' "${COMPREPLY[@]}"
}

@test "completion: init completes a directory as its first argument" {
  run complete_words git-subtrees init vend
  [[ "$output" == *"vendor"* ]]
}

@test "completion: init completes the path after --base and its value" {
  run complete_words git-subtrees init --base main vend
  [[ "$output" == *"vendor"* ]]
}

@test "completion: init completes the path after --base=<value> split by bash" {
  run complete_words git-subtrees init --base = main vend
  [[ "$output" == *"vendor"* ]]
}

@test "completion: init offers no directory for the url" {
  run complete_words git-subtrees init --base main vendor/a vend
  [ -z "$output" ]
}

@test "completion: init completes branches after --base" {
  run complete_words git-subtrees init --base ma
  [[ "$output" == *"main"* ]]
}

# Prints what zsh lists for a command line, one candidate per line.
zsh_complete() {
  command -v zsh >/dev/null || skip "zsh not installed"
  zsh "$BATS_TEST_DIRNAME/helpers/zsh-complete.zsh" \
    "$BATS_TEST_DIRNAME/../completions/git-subtrees.zsh" "$1"
}

# Prints what fish completes for a command line, one candidate per line.
fish_complete() {
  command -v fish >/dev/null || skip "fish not installed"
  LINE="$1" fish --no-config -c 'source $argv[1]; complete -C "$LINE"' \
    "$BATS_TEST_DIRNAME/../completions/git-subtrees.fish" | cut -f1
}

@test "zsh completion: subcommands" {
  run zsh_complete "git-subtrees pu"
  [[ "$output" == *"pull"* && "$output" == *"push"* ]]
}

@test "zsh completion: push completes subtree paths" {
  run zsh_complete "git-subtrees push vendor/"
  [[ "$output" == *"vendor/a"* ]]
}

@test "zsh completion: init completes the path, also after --base" {
  run zsh_complete "git-subtrees init vend"
  [[ "$output" == *"vendor/"* ]]
  run zsh_complete "git-subtrees init --base main vend"
  [[ "$output" == *"vendor/"* ]]
  run zsh_complete "git-subtrees init --base=main vend"
  [[ "$output" == *"vendor/"* ]]
}

@test "zsh completion: init offers no directory for the url" {
  run zsh_complete "git-subtrees init vendor/a vend"
  [ -z "$output" ]
}

@test "zsh completion: init completes branches for --base" {
  run zsh_complete "git-subtrees init --base=ma"
  [[ "$output" == *"main"* ]]
}

@test "fish completion: subcommands" {
  run fish_complete "git-subtrees pu"
  [[ "$output" == *"pull"* && "$output" == *"push"* ]]
}

@test "fish completion: push completes subtree paths" {
  run fish_complete "git-subtrees push vendor/"
  [[ "$output" == *"vendor/a"* ]]
}

@test "fish completion: init completes the path, also after --base" {
  run fish_complete "git-subtrees init vend"
  [[ "$output" == *"vendor/"* ]]
  run fish_complete "git-subtrees init --base main vend"
  [[ "$output" == *"vendor/"* ]]
  run fish_complete "git-subtrees init --base=main vend"
  [[ "$output" == *"vendor/"* ]]
}

@test "fish completion: init offers no directory for the url" {
  run fish_complete "git-subtrees init vendor/a vend"
  [ -z "$output" ]
}

@test "fish completion: init completes branches for --base" {
  run fish_complete "git-subtrees init --base ma"
  [[ "$output" == *"main"* ]]
}
