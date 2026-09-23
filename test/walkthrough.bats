# Keeps docs/last-synced-commit/README.md honest: the walkthrough script it
# quotes must keep producing the states its table claims.

@test "walkthrough: reports the states documented in docs/last-synced-commit/README.md" {
  run bash "$BATS_TEST_DIRNAME/../docs/last-synced-commit/walkthrough.sh" \
    --dir "$BATS_TEST_TMPDIR/walkthrough"
  [ "$status" -eq 0 ]

  local expected actual
  # Step 5 relies on recognising our own push (README, "After a push").
  expected="up-to-date
missing-at-head (unchanged vs base 'main')
missing-at-head (changed vs base 'main')
up-to-date
push
missing-at-head (changed vs base 'main')
up-to-date
missing-at-head (changed vs base 'main')"
  actual="$(printf '%s\n' "$output" | sed -n 's/^  => //p')"
  [ "$actual" = "$expected" ]
}

@test "walkthrough: ignores the developer's global git config" {
  # A global config that would make every quiet `git commit` step fail.
  local hostile="$BATS_TEST_TMPDIR/hostile-gitconfig"
  printf '[commit]\n\tgpgsign = true\n[gpg]\n\tprogram = /nonexistent\n' >"$hostile"
  GIT_CONFIG_GLOBAL="$hostile" run bash \
    "$BATS_TEST_DIRNAME/../docs/last-synced-commit/walkthrough.sh" \
    --dir "$BATS_TEST_TMPDIR/walkthrough"
  [ "$status" -eq 0 ]
}

@test "walkthrough: --dir without a value prints usage instead of an unbound variable" {
  run bash "$BATS_TEST_DIRNAME/../docs/last-synced-commit/walkthrough.sh" --dir
  [ "$status" -eq 1 ]
  [[ "$output" == *"--dir needs a path"* ]]
  [[ "$output" == *"usage:"* ]]
}
