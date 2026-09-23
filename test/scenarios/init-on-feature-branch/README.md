# Scenario: init-on-feature-branch

You start using a remote on a feature branch, before the remote has that
branch.

- **Monorepo**: on `feature`, cut from `main`. No `vendor/a` yet. The base
  branch is `main`, via `init.defaultBranch`.
- **Remote**: only has `main`, at `seed`. No `feature` branch.

`git subtrees init vendor/a <upstream>` can't add `feature`, so it adds the
remote's `main` instead -- the branch named like the monorepo's base branch.
This matches `push`: the subtree now differs from the monorepo's `main`, so
the first `git subtrees push` creates `feature` on the remote, on top of its
`main`.

Expected result: `vendor/a` contains `seed`; `classify_subtree "vendor/a"
"feature"` is `missing-at-head` with `changes_vs_base` `yes`; `push`
creates `feature` on the remote as a descendant of `main`.

Built by `scenario_init_on_feature_branch` in `setup.bash`.
