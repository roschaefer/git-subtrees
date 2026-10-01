# Scenario: push-protection

Why `git subtrees init` sets a push URL that Git can't push to, and what
that changes.

- **Monorepo**: a subtree `vendor/a`, plus a folder `internal/` that must
  never leave the monorepo. The remote `vendor/a` was added with a plain
  `git remote add`, so it isn't push-protected yet.
- **Remote**: one commit (`seed`), the same as `vendor/a`.

## The problem

A subtree remote is an ordinary Git remote. `git subtree push` sends it
the output of `git subtree split`: a history with only the subtree's
files. Any other push to it sends the monorepo's own commits, with **every
folder** in them.

Typing `git push vendor/a main` by mistake is the obvious way, but not the
only one:

- **`push.autoSetupRemote` on a repo whose only remote is a subtree
  remote.** A plain `git push` on a new branch picks the only remote,
  pushes the monorepo there and makes it the upstream. A monorepo without
  `origin` (e.g. local-only, publishing parts of itself) is exactly the
  setup where this happens. The output below shows it.
- **Once a branch's upstream is a subtree remote**, every later plain
  `git push`, the IDE's "Sync" button or LazyGit's `P` goes there. Besides
  `push.autoSetupRemote` and `git push -u`, `remote.pushDefault` and
  `branch.<name>.pushRemote` can point there too. `git switch <name>` also
  creates a branch tracking a subtree remote when only that remote has a
  branch `<name>`.
- **LazyGit**, for a branch without an upstream, suggests `origin` if it
  exists and otherwise the first remote. Without `origin`, a subtree remote
  is one Enter away. With `push.default=current` it doesn't ask at all.
- **Shell history.** `git push vendor/a main` and
  `git subtree push --prefix=vendor/a vendor/a main` both match a reverse
  search for `push vendor/a`.
- `git push --all <remote>` and `git push --mirror <remote>`.

When the remote already has the branch, a plain push is usually rejected
as non-fast-forward. The dangerous cases are **new branches** and
**`--force`**.

It's hard to undo: deleting the branch afterwards doesn't unpublish
anything. GitHub keeps the commits reachable by their hash until support
purges them, and anyone who fetched or forked in the meantime has a copy
([an example with ~4000 commits pushed by
mistake](https://github.com/orgs/community/discussions/21995)). So this
shouldn't be left to the user being careful.
[Issue #50](https://github.com/roschaefer/git-subtrees/issues/50) has the
other options that were considered.

## The protection

A remote can have a push URL that differs from its fetch URL.
`git subtrees init` sets it to `BLOCKED by git-subtrees -- push with => git subtrees push`.
Fetching is unaffected. Any push to the remote by its name fails, since Git
finds no repository at that URL, and the error message says what to do.
`git push --no-verify` doesn't get around it, and no hook is involved.

`git subtrees push` rewrites exactly that URL to the fetch URL for its own
push, and only for that push. It still pushes by the remote's name, so Git
updates the remote's tracking refs as before: no `fetch` is needed after a
push, protected or not.

The protection is part of the local repository's config, like the remote
itself, so every clone of the monorepo needs it again. `git subtrees init`
sets it for a remote that has no push URL yet. A remote with a push URL of
its own keeps it, and `git subtrees push` pushes there; it just doesn't
count as protected.

## Output

`scenario_push_protection` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_push_protection
```
-->

`status` marks the remote as not protected (in red, on a terminal):

```scrut
$ git subtrees status
ok   vendor/a [NOT push-protected] (up to date)
```

Unprotected, `git subtrees push` works as you'd expect:

```scrut
$ echo "first change" >>vendor/a/file.txt && git commit -qam "change vendor/a"
```

```scrut
$ git subtrees push
git push using:  vendor/a main
To $UPSTREAM
   bde4164..88c45ad  88c45ad56d81d8a01be6d6dd6a51e910048361f8 -> main
ok   vendor/a: pushed
```

But nothing stops the slip either. This monorepo has no `origin`, so with
`push.autoSetupRemote`, a plain `git push` on a new branch picks
`vendor/a`:

```scrut
$ git config push.autoSetupRemote true && git switch -q -c topic
```

```scrut
$ git push
To $UPSTREAM
 * [new branch]      topic -> topic
branch 'topic' set up to track 'vendor/a/topic'.
```

That published the whole monorepo, `internal/` included:

```scrut
$ git -C "$UPSTREAM" ls-tree -r --name-only topic
internal/notes.txt
vendor/a/file.txt
```

Protect the remote, as `git subtrees status -h` shows (or by running
`git subtrees init vendor/a <url>` again):

```scrut
$ git remote set-url --push vendor/a 'BLOCKED by git-subtrees -- push with => git subtrees push'
```

`topic` now tracks `vendor/a`, so every later plain `git push` would go
there. Now it fails, before anything is sent:

```scrut
$ echo "more notes" >>internal/notes.txt && git commit -qam "more internal notes"
```

```scrut
$ git push
fatal: 'BLOCKED by git-subtrees -- push with => git subtrees push' does not appear to be a git repository
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists.
[128]
```

Back on `main`, `status` shows the remote as protected:

```scrut
$ git switch -q main
```

```scrut
$ git subtrees status
ok   vendor/a [push-protected] (up to date)
```

A plain `git subtree push` fails too, since it also pushes by the remote's
name. Use `git subtrees push`:

```scrut
$ git subtree push --prefix=vendor/a vendor/a main
git push using:  vendor/a main
fatal: 'BLOCKED by git-subtrees -- push with => git subtrees push' does not appear to be a git repository
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists.
[128]
```

```scrut
$ echo "second change" >>vendor/a/file.txt && git commit -qam "change vendor/a again"
```

```scrut
$ git subtrees push
git push using:  vendor/a main
To $UPSTREAM
   88c45ad..d4528c1  d4528c1d6dd7e914809f9cf9d4bd1e3061dcbba2 -> main
ok   vendor/a: pushed
```

The output is the same as without the protection, and so is the result:
the tracking ref moved with the push, so `status` is up to date without a
`fetch`:

```scrut
$ git subtrees status
ok   vendor/a [push-protected] (up to date)
```
