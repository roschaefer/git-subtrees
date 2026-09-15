# Scenario: init-unrelated-content

A directory that will become a subtree already has content, and that
content has nothing to do with the remote being connected -- the "move it
aside" case for `git subtrees init`.

- **Monorepo**: `vendor/a` exists with a locally-created file, committed,
  never a subtree.
- **Remote**: has its own unrelated `seed` commit.
- **No remote is registered yet** -- `cmd_init` is expected to register it
  itself as its first step.

Expected `git subtrees init vendor/a <upstream>` result: refuses with an
error, telling the user to `mv vendor/a vendor/a.bak` and re-run.

Built by `scenario_init_unrelated_content` in `setup.bash`.
