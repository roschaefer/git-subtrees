# Scenario: push-ahead

Local made a commit under the subtree path since connecting; the remote
hasn't moved.

- **Monorepo (`vendor/a`)**: connected at `seed`, then one more local
  commit under `vendor/a`.
- **Remote**: still at `seed`, unchanged.
- **Common ancestor**: yes -- the connection point (`seed`).

Expected `classify_subtree` result: `push`.

Built by `scenario_push_ahead` in `setup.bash`.
