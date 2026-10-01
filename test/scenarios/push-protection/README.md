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
folder** in them. That's a slip of the fingers, `git push vendor/a main`
instead of `git push origin main`, but it doesn't have to be one:

- With `push.autoSetupRemote` and no `origin`, a plain `git push` on a new
  branch picks the only remote there is.
- Once a branch's upstream is a subtree remote, every plain `git push`, an
  IDE's "Sync" button, or a Git GUI's push goes there.
- A reverse search for `push vendor/a` in your shell history finds
  `git push vendor/a main` as well as `git subtree push ... vendor/a main`.

When the remote already has the branch, a plain push is usually rejected
as non-fast-forward. New branches and `--force` go through. Deleting the
branch afterwards doesn't unpublish anything: hosts like GitHub keep the
commits reachable by their hash, and anyone who fetched in the meantime has
a copy. [Issue #50](https://github.com/roschaefer/git-subtrees/issues/50)
has the details and the other options that were considered.

## The protection

A remote can have a push URL that differs from its fetch URL.
`git subtrees init` sets it to `push with git subtrees push, not git push`.
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

`status` warns about the remote that isn't protected:

```scrut
$ git subtrees status
ok   vendor/a [NOT push-protected] (up to date)
!!   vendor/a: a plain 'git push vendor/a' sends the whole monorepo there -- push-protect it with:

  git remote set-url --push vendor/a 'push with git subtrees push, not git push'

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

But so does the slip. A plain push to a new branch publishes the whole
monorepo, `internal/` included:

```scrut
$ git push vendor/a main:oops
To $UPSTREAM
 * [new branch]      main -> oops
```

```scrut
$ git -C "$UPSTREAM" ls-tree -r --name-only oops
internal/notes.txt
vendor/a/file.txt
```

Protect the remote with the command `status` printed (or by running
`git subtrees init vendor/a <url>` again):

```scrut
$ git remote set-url --push vendor/a 'push with git subtrees push, not git push'
```

```scrut
$ git subtrees status
ok   vendor/a [push-protected] (up to date)
```

Now the same slip fails, before anything is sent:

```scrut
$ git push vendor/a main:oops-again
fatal: 'push with git subtrees push, not git push' does not appear to be a git repository
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists.
[128]
```

So does a plain `git subtree push`, which goes through the remote's name
too. Use `git subtrees push`:

```scrut
$ git subtree push --prefix=vendor/a vendor/a main
git push using:  vendor/a main
fatal: 'push with git subtrees push, not git push' does not appear to be a git repository
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
