# Scenario: feature-branch-never-synced

The remote has no branch for the current one, and the subtree path was
never brought in via `git subtree add`/`pull`, so it shares no history with
the remote's default branch.

- **Monorepo (`vendor/a`)**: directory created by a plain commit on a
  `feature` branch; remote `vendor/a` registered and fetched.
- **Remote**: only has `main`. No `feature` branch.

Expected `classify_subtree "vendor/a" "feature"` result:
`unrelated-history`, measured against the default branch. `push` refuses
and prints recovery commands; re-adopting the remote's version uses
`main`, since `feature` doesn't exist there.

Built by `scenario_feature_branch_never_synced` in `setup.bash`.
