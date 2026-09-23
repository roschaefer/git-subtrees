# Scenario: diverged-then-pulled

Both sides changed different files, then the remote's change was pulled in.
The local change is still waiting to be pushed.

- **Monorepo (`vendor/a`)**: added at `seed`, then a local commit adding
  `local.txt`, then `git subtree pull --squash` of the upstream change. The
  merge has no conflict.
- **Remote**: `seed`, then a commit adding `upstream.txt`. It has never
  seen `local.txt`.

The pull moved the sync point to the remote's tip, but `vendor/a` still has
`local.txt` on top of it. Local changes must be measured against what the
sync point recorded from the remote, not against the merge commit that
brought it in: the merge commit already contains `local.txt`, which would
hide it from `push`.

Expected `classify_subtree` result: `push`.

Built by `scenario_diverged_then_pulled` in `setup.bash`.
