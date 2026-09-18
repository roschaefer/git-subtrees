# Keeps docs/last-synced-commit/README.md honest: the walkthrough script it
# quotes must keep producing the states its table claims.

@test "walkthrough: reports the states documented in docs/last-synced-commit/README.md" {
  run bash "$BATS_TEST_DIRNAME/../docs/last-synced-commit/walkthrough.sh" \
    --dir "$BATS_TEST_TMPDIR/walkthrough"
  [ "$status" -eq 0 ]

  local expected actual
  # Step 5 is a known limitation (README, "Known limitations"): if it gets
  # fixed, update this list and the README together.
  expected="up-to-date
missing-at-head (unchanged vs base 'main')
missing-at-head (changed vs base 'main')
up-to-date
diverged
missing-at-head (changed vs base 'main')
up-to-date
missing-at-head (changed vs base 'main')"
  actual="$(printf '%s\n' "$output" | sed -n 's/^  => //p')"
  [ "$actual" = "$expected" ]
}
