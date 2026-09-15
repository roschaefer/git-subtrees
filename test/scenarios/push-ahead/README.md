# Scenario: push-ahead

Local made a commit under the subtree path since it was added; the remote
hasn't moved.

- **Monorepo (`vendor/a`)**: added at `seed`, then one more local
  commit under `vendor/a`.
- **Remote**: still at `seed`, unchanged.
- **Common ancestor**: yes -- the add point (`seed`).

Expected `classify_subtree` result: `push`.

Built by `scenario_push_ahead` in `setup.bash`.
