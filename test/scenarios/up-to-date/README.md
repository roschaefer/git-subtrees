# Scenario: up-to-date

<!-- Builds this scenario; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../scrut-setup.sh"
```
-->

A subtree freshly added via `git subtree add --squash` and never
touched again on either side.

- **Monorepo (`vendor/a`)**: one commit (`seed`), added, no local
  changes since.
- **Remote**: one commit (`seed`), unchanged since add.
- **Common ancestor**: yes -- they were just added; the tree contents
  are identical.

## Output

Nothing to do on either side:

```scrut
$ git subtrees status
ok   vendor/a -> $UPSTREAM (up to date)
```

```scrut
$ git subtrees pull
ok   vendor/a fetched
ok   vendor/a: nothing to pull
```

```scrut
$ git subtrees push
ok   vendor/a: nothing to push
```

Built by `scenario_up_to_date` in `setup.bash`.
