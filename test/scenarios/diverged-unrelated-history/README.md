# Scenario: diverged-unrelated-history

Both sides moved since the subtree was added, but the remote's entire history was
then replaced with something that shares no ancestry with what was last
synced -- e.g. the upstream repo was rebuilt from scratch.

- **Monorepo (`vendor/a`)**: added at `seed`, then one local commit
  under `vendor/a`.
- **Remote**: the original bare repo is deleted and recreated from
  scratch with a brand new, unrelated root commit.
- **Common ancestor**: **no**. `git merge-base` between the commit this
  tool last synced against (recorded in the `git-subtree-split:` trailer
  of the squash commit) and the remote's current tip finds nothing.

This is the case `git subtrees pull`/`push` must **not** try to
auto-merge: there's no principled three-way merge when two sides don't
share history, only a human decision to keep one side and discard the
other's. Both commands detect this and print two manual recovery command
sequences instead of attempting anything:

```sh
# accept the remote's version, discarding local changes under vendor/a:
git rm -r vendor/a
git commit -m 'remove vendor/a before re-adopting it from its remote'
git subtree add --prefix=vendor/a vendor/a main --squash

# OR: accept the local (monorepo) version, overwriting vendor/a's history:
git subtree split --prefix=vendor/a -b tmp-split-a
git push --force vendor/a tmp-split-a:main
git branch -D tmp-split-a
```

Both sequences were verified by hand against this exact scenario shape
before being wired into `lib/common.sh`'s `print_unrelated_history_guidance`.

Expected `classify_subtree` result: `unrelated-history`.

Built by `scenario_diverged_unrelated_history` in `setup.bash`.
