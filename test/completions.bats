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

# Skips the test unless shell $1 is installed. Call it outside `run`: under
# `run`, skip only ends run's subshell, and the test goes on with empty
# output.
require_shell() {
  command -v "$1" >/dev/null || skip "$1 not installed"
}

# Prints what zsh lists for a command line, one candidate per line.
zsh_complete() {
  zsh "$BATS_TEST_DIRNAME/helpers/zsh-complete.zsh" \
    "$BATS_TEST_DIRNAME/../completions/git-subtrees.zsh" "$1"
}

# Prints what fish completes for a command line, one candidate per line.
fish_complete() {
  LINE="$1" fish --no-config -c 'source $argv[1]; complete -C "$LINE"' \
    "$BATS_TEST_DIRNAME/../completions/git-subtrees.fish" | cut -f1
}

@test "zsh completion: subcommands" {
  require_shell zsh
  run zsh_complete "git-subtrees pu"
  [[ "$output" == *"pull"* && "$output" == *"push"* ]]
}

@test "zsh completion: push completes subtree paths" {
  require_shell zsh
  run zsh_complete "git-subtrees push vendor/"
  [[ "$output" == *"vendor/a"* ]]
}

@test "zsh completion: init completes the path, also after --base" {
  require_shell zsh
  run zsh_complete "git-subtrees init vend"
  [[ "$output" == *"vendor/"* ]]
  run zsh_complete "git-subtrees init --base main vend"
  [[ "$output" == *"vendor/"* ]]
  run zsh_complete "git-subtrees init --base=main vend"
  [[ "$output" == *"vendor/"* ]]
}

@test "zsh completion: init offers no directory for the url" {
  require_shell zsh
  run zsh_complete "git-subtrees init vendor/a vend"
  [ -z "$output" ]
}

@test "zsh completion: init completes branches for --base" {
  require_shell zsh
  run zsh_complete "git-subtrees init --base=ma"
  [[ "$output" == *"main"* ]]
}

@test "fish completion: subcommands" {
  require_shell fish
  run fish_complete "git-subtrees pu"
  [[ "$output" == *"pull"* && "$output" == *"push"* ]]
}

@test "fish completion: push completes subtree paths" {
  require_shell fish
  run fish_complete "git-subtrees push vendor/"
  [[ "$output" == *"vendor/a"* ]]
}

@test "fish completion: init completes the path, also after --base" {
  require_shell fish
  run fish_complete "git-subtrees init vend"
  [[ "$output" == *"vendor/"* ]]
  run fish_complete "git-subtrees init --base main vend"
  [[ "$output" == *"vendor/"* ]]
  run fish_complete "git-subtrees init --base=main vend"
  [[ "$output" == *"vendor/"* ]]
}

@test "fish completion: init offers no directory for the url" {
  require_shell fish
  run fish_complete "git-subtrees init vendor/a vend"
  [ -z "$output" ]
}

@test "fish completion: init completes branches for --base" {
  require_shell fish
  run fish_complete "git-subtrees init --base ma"
  [[ "$output" == *"main"* ]]
}
