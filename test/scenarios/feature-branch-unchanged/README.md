# Scenario: feature-branch-unchanged

The monorepo is on a feature branch the subtree's remote has never heard
of, and nothing under the subtree path has changed since it was added.

- **Monorepo (`vendor/a`)**: added at `seed` on `main`, then switched to
  a new `feature` branch with no further commits.
- **Remote**: only has `main`, at `seed`. No `feature` branch.

Expected `classify_subtree "vendor/a" "feature"` result: `up-to-date`,
measured against the default branch (`SUBTREE_BASELINE_BRANCH=main`).
`push` must not create `feature` on the remote.

Built by `scenario_feature_branch_unchanged` in `setup.bash`.
