# Scenario: pushed-then-changed

The monorepo pushed a change, then changed the subtree again. The remote
has nothing but that push.

- **Monorepo (`vendor/a`)**: added at `seed`, then a commit that was
  pushed with `git subtree push`, then another local commit.
- **Remote**: `seed`, then the commit `git subtree split` made from the
  pushed one.
- **Sync point**: still `seed` -- a push doesn't move it.

Compared with the sync point alone, both sides changed. But the remote's
tip is recognisably our own push: `git subtree split` copies the author,
dates and message of the local commit it came from, and its tree is
`vendor/a` at that commit. So only local changed since, and a push
fast-forwards the remote.

Expected `classify_subtree` result: `push`. `common.bats` also covers
what happens when someone else commits on the remote after that push:
`diverged`, or `pull` if the monorepo didn't change since its push.

Built by `scenario_pushed_then_changed` in `setup.bash`.
