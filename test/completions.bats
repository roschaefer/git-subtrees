# Drives the bash completion function directly, the way bash calls it: with
# the command line split into COMP_WORDS, including bash's split at "=".

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

@test "completion: push completes subtree paths" {
  run complete_words git-subtrees push vend
  [ "$output" = "vendor/a" ]
}

@test "completion: push completes branches for '--base <value>'" {
  run complete_words git-subtrees push --base ma
  [ "$output" = "main" ]
}

# bash passes "--base=ma" as "--base", "=", "ma".
@test "completion: push completes branches for '--base=<value>'" {
  run complete_words git-subtrees push --base = ma
  [ "$output" = "main" ]
}

# bash passes "--base=" as "--base", "=", with "=" as the current word.
@test "completion: push completes branches right after '--base='" {
  run complete_words git-subtrees push --base =
  [ "$output" = "main" ]
}

@test "completion: diff and status complete branches for '--base=<value>'" {
  run complete_words git-subtrees diff --base = ma
  [ "$output" = "main" ]
  run complete_words git-subtrees status --base = ma
  [ "$output" = "main" ]
}

@test "completion: push completes paths again after a '--base=<value>'" {
  run complete_words git-subtrees push --base = main vend
  [ "$output" = "vendor/a" ]
}

# `compgen -W` expands its word list, so a branch named like $(cmd) -- valid,
# and any remote can publish one -- would run cmd on <TAB>.
@test "completion: a branch name with a command substitution is never run" {
  local name='x$(touch${IFS}pwned)'
  git update-ref "refs/heads/$name" HEAD

  run complete_words git-subtrees push --base x
  [ ! -e pwned ]
  # Offered shell-quoted, so running the completed line doesn't run it either.
  [ "$output" = 'x\$\(touch\$\{IFS\}pwned\)' ]
  [ "$(eval "printf '%s' $output")" = "$name" ]
}

@test "completion: a subtree path with a command substitution is never run" {
  local name='vendor/$(touch${IFS}pwned)'
  mkdir -p "$name"
  git remote add "$name" "$BATS_TEST_TMPDIR/unused.git"

  run complete_words git-subtrees push 'vendor/$'
  [ ! -e pwned ]
  [ "$output" = 'vendor/\$\(touch\$\{IFS\}pwned\)' ]
}

@test "completion: init offers a directory with a command substitution quoted" {
  mkdir 'z$(touch${IFS}pwned)'
  run complete_words git-subtrees init z
  [ ! -e pwned ]
  [ "$output" = 'z\$\(touch\$\{IFS\}pwned\)' ]
}
