# Scenario: not-connected

A remote is registered and its name matches an existing directory, but it
has never been fetched -- `refs/remotes/vendor/a/*` doesn't exist at all
yet.

- **Monorepo**: an empty `vendor/a` directory exists; `git remote add
  vendor/a <upstream>` has been run, but `git fetch` never has.
- **Remote**: has a `seed` commit, but we don't know that locally yet.

## Output

The output below is real. `just docs-check` builds this state with
`scenario_not_connected`,
the function in [`setup.bash`](setup.bash) that the bats tests call too,
and then runs each command.

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_not_connected
```
-->

```scrut
$ git subtrees status
??   vendor/a -> $UPSTREAM (never fetched -- run 'git subtrees fetch vendor/a')
```
