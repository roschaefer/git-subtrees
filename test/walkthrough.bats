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
up-to-date (vs default branch 'main')
push (vs default branch 'main')
up-to-date
diverged
push (vs default branch 'main')
up-to-date
push (vs default branch 'main')"
  actual="$(printf '%s\n' "$output" | sed -n 's/^  => //p')"
  [ "$actual" = "$expected" ]
}
