# Scenario: feature-branch-never-synced

The remote has no branch for the current one, and the subtree path was
never brought in via `git subtree add`/`pull`, so there is no sync point
to measure local changes against.

- **Monorepo (`vendor/a`)**: directory created by a plain commit on a
  `feature` branch; remote `vendor/a` registered and fetched.
- **Remote**: only has `main`. No `feature` branch.

Expected `classify_subtree "vendor/a" "feature"` result: `missing-at-head`
with `SUBTREE_LOCAL_CHANGES=unknown`. `push` refuses and prints the manual
`git subtree push` command.

Built by `scenario_feature_branch_never_synced` in `setup.bash`.
