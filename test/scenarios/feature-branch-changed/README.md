# Scenario: feature-branch-changed

Like `feature-branch-unchanged`, but the subtree has local changes on the
feature branch.

- **Monorepo (`vendor/a`)**: added at `seed` on `main`, then a new
  `feature` branch with one commit under `vendor/a`.
- **Remote**: only has `main`, at `seed`. No `feature` branch.

Expected `classify_subtree "vendor/a" "feature"` result: `push`, measured
against the default branch (`SUBTREE_BASELINE_BRANCH=main`). `push`
creates `feature` on the remote.

Built by `scenario_feature_branch_changed` in `setup.bash`.
