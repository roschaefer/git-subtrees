# Scenario: diverged-common-ancestor

Both sides moved independently since connecting, but they still share a
real sync point: the connection commit itself.

- **Monorepo (`vendor/a`)**: connected at `seed`, then one local commit
  under `vendor/a`.
- **Remote**: `seed`, then one independent upstream commit.
- **Common ancestor**: yes -- `seed`, the point they were connected at.

This is the "ordinary" divergence case: `git subtrees pull` still attempts
its normal `git subtree pull --squash`, which may hit a normal merge
conflict resolved by editing the file and running plain `git commit`.
Contrast with `diverged-unrelated-history`, where no such attempt is made.

Expected `classify_subtree` result: `diverged`.

Built by `scenario_diverged_common_ancestor` in `setup.bash`.
