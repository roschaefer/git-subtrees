# Drives the bash completion function directly, the way bash calls it.

setup() {
  load 'helpers/fixtures'
  # shellcheck disable=SC1091
  source "$BATS_TEST_DIRNAME/../completions/git-subtrees.bash"
  init_monorepo "$BATS_TEST_TMPDIR/monorepo"
  cd "$BATS_TEST_TMPDIR/monorepo"
  mkdir -p vendor/a
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
