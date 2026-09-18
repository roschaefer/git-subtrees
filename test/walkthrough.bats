# Keeps docs/last-synced-commit/README.md honest: the walkthrough script it
# quotes must keep producing the states its table claims.

@test "walkthrough: reports the states documented in docs/last-synced-commit/README.md" {
  run bash "$BATS_TEST_DIRNAME/../docs/last-synced-commit/walkthrough.sh" \
    --dir "$BATS_TEST_TMPDIR/walkthrough"
  [ "$status" -eq 0 ]

  local expected actual
  # Steps 5 and 6 are known limitations (README, "Known limitations"): if
  # they get fixed, update this list and the README together.
  expected="up-to-date
missing-at-head, local changes: no
missing-at-head, local changes: yes
up-to-date
diverged
missing-at-head, local changes: yes
up-to-date
missing-at-head, local changes: yes"
  actual="$(printf '%s\n' "$output" | sed -n 's/^  => //p')"
  [ "$actual" = "$expected" ]
}
