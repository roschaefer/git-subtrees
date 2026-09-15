# Scenario: pull-ahead

The remote gained a commit since connecting; the monorepo hasn't touched
the subtree path.

- **Monorepo (`vendor/a`)**: connected at `seed`, no local changes since.
- **Remote**: `seed`, then one more commit (`upstream change`).
- **Common ancestor**: yes -- the connection point (`seed`).

The scenario also fetches once during setup, so `refs/remotes/vendor/a/*`
already reflects the remote's new commit (mirroring what a real `status`
run needs, since `status` never fetches on its own).

Expected `classify_subtree` result: `pull`.

Built by `scenario_pull_ahead` in `setup.bash`.
