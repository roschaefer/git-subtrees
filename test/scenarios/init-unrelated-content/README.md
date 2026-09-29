# Scenario: init-unrelated-content

<!-- Builds this scenario; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../scrut-setup.sh"
```
-->

A directory that will become a subtree already has content, and that
content has nothing to do with the remote being added -- the "move it
aside" case for `git subtrees init`.

- **Monorepo**: `vendor/a` exists with a locally-created file, committed,
  never a subtree.
- **Remote**: has its own unrelated `seed` commit.
- **No remote is registered yet** -- `cmd_init` is expected to register it
  itself as its first step.

## Output

```scrut
$ git subtrees init vendor/a "$UPSTREAM"
===  vendor/a: registering remote -> $UPSTREAM
===  vendor/a: fetching
ok   vendor/a fetched
!!   vendor/a: directory exists with content unrelated to $UPSTREAM
!!   move it aside and re-run: mv vendor/a vendor/a.bak && git subtrees init vendor/a $UPSTREAM
[1]
```

Built by `scenario_init_unrelated_content` in `setup.bash`.
