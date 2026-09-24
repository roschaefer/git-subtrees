# Scenario: pushed-then-changed

The monorepo pushed a change, then changed the subtree again. The remote
has nothing but that push.

- **Monorepo (`vendor/a`)**: added at `seed`, then a commit that was
  pushed with `git subtrees push` (`push_one`), then another local commit.
- **Remote**: `seed`, then the commit `git subtree split` made from the
  pushed one.
- **Sync point**: the squash commit `push_one` wrote after the push.

The sync point matches the remote's tip, so only local changed since, and a
push fast-forwards the remote.

Expected `classify_subtree` result: `push`. `common.bats` also covers
what happens when someone else commits on the remote after that push:
`diverged`, or `pull` if the monorepo didn't change since its push.

Built by `scenario_pushed_then_changed` in `setup.bash`.
