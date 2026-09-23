# Scenario: nested-subtrees

One subtree folder inside another: remotes `vendor/pkg` and
`vendor/pkg/extra`, both matching existing folders.

- **Monorepo**: `vendor/pkg` added at `seed`, then a folder
  `vendor/pkg/extra` with its own remote.
- **Remote**: one commit (`seed`). Both remotes point at it; only the
  names matter here.

Git 2.51+ refuses `git remote add vendor/pkg/extra` once `vendor/pkg`
exists, but older versions accept it, so the setup writes the remote to the
config directly.

Nesting breaks the tool's assumptions:

- `vendor/pkg`'s content includes `vendor/pkg/extra`, so it never matches
  its own remote and always looks like unrelated history.
- `refs/remotes/vendor/pkg/*` includes the inner remote's refs, so a
  never-fetched outer remote looks fetched.
- The recovery commands for unrelated history would `git rm -r vendor/pkg`
  (deleting the inner subtree) or force-push it with the inner subtree's
  files included.

Expected result: every command fails with "nested subtrees are not
supported" before doing anything, and `git subtrees init` refuses to
register a nested remote.

Built by `scenario_nested_subtrees` in `setup.bash`.
