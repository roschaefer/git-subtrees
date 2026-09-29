# Scenario: not-connected

<!-- Builds this scenario; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../scrut-setup.sh"
```
-->

A remote is registered and its name matches an existing directory, but it
has never been fetched -- `refs/remotes/vendor/a/*` doesn't exist at all
yet.

- **Monorepo**: an empty `vendor/a` directory exists; `git remote add
  vendor/a <upstream>` has been run, but `git fetch` never has.
- **Remote**: has a `seed` commit, but we don't know that locally yet.

## Output

```scrut
$ git subtrees status
??   vendor/a -> $UPSTREAM (never fetched -- run 'git subtrees fetch vendor/a')
```

Built by `scenario_not_connected` in `setup.bash`.
