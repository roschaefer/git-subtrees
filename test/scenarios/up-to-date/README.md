# Scenario: up-to-date

A subtree freshly connected via `git subtree add --squash` and never
touched again on either side.

- **Monorepo (`vendor/a`)**: one commit (`seed`), connected, no local
  changes since.
- **Remote**: one commit (`seed`), unchanged since connection.
- **Common ancestor**: yes -- they were just connected; the tree contents
  are identical.

Expected `classify_subtree` result: `up-to-date`.

Built by `scenario_up_to_date` in `setup.bash`.
