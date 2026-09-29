# Diverged history

A subtree has diverged when both the monorepo and the remote changed it
since the last sync. This walkthrough in the [playground](README.md) makes
both sides change the same line, then resolves the conflict.

<!-- Builds a fresh playground; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

First, bring `vendor/pkg-a` up to date:

```scrut
$ git subtrees pull vendor/pkg-a
ok   vendor/pkg-a fetched
Merge made by the 'ort' strategy.
 vendor/pkg-a/file.txt | 1 +
 1 file changed, 1 insertion(+)
ok   vendor/pkg-a: pulled
```

## Both sides change

The monorepo and the remote each append a line to the same file:

```scrut
$ echo "a local fix" >>vendor/pkg-a/file.txt && git commit -qam "pkg-a: a local fix"
```

```scrut
$ simulate-remote-change vendor/pkg-a "pkg-a: an upstream fix"
ok   vendor/pkg-a: pushed a new commit upstream ('pkg-a: an upstream fix')
     git subtrees status   # to see it
     git subtrees pull     # to bring it in
```

Once fetched, `status` reports the subtree as `diverged`:

```scrut
$ git subtrees fetch
ok   vendor/pkg-a fetched (main moved 57a78eb..9f14d0d)
```

```scrut
$ git subtrees status vendor/pkg-a
ok   vendor/pkg-a -> $PLAYGROUND/upstream/pkg-a.git (diverged)
 file.txt | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
```

## Pull first

The remote refuses a push that would drop its commit:

```scrut
$ git subtrees push
git push using:  vendor/pkg-a main
To $PLAYGROUND/upstream/pkg-a.git
 ! [rejected]        f1707763740dac634368f95f66cbd0bdf84d24e7 -> main (non-fast-forward)
error: failed to push some refs to '$PLAYGROUND/upstream/pkg-a.git'
hint: Updates were rejected because the tip of your current branch is behind
hint: its remote counterpart. If you want to integrate the remote changes,
hint: use 'git pull' before pushing again.
hint: See the 'Note about fast-forwards' in 'git push --help' for details.
!!   vendor/pkg-a: push failed
!!   Failed: vendor/pkg-a
[1]
```

`pull` squash-merges the remote's side. The same line changed on both
sides, so git stops with a conflict:

```scrut
$ git subtrees pull
ok   vendor/pkg-a fetched
Auto-merging vendor/pkg-a/file.txt
CONFLICT (content): Merge conflict in vendor/pkg-a/file.txt
Automatic merge failed; fix conflicts and then commit the result.
!!   vendor/pkg-a: pull failed -- resolve any conflicts, 'git commit', then re-run pull
!!   Failed: vendor/pkg-a
[1]
```

```scrut
$ cat vendor/pkg-a/file.txt
pkg-a: seed
pkg-a: a second commit, after connecting
<<<<<<< HEAD
a local fix
=======
pkg-a: an upstream fix
>>>>>>> ed1183628db303e82765d92df3d655f05ba3b48c
```

## Resolve and push

Resolve it as for any merge: keep both lines, then commit.

```scrut
$ cat >vendor/pkg-a/file.txt <<'EOF'
> pkg-a: seed
> pkg-a: a second commit, after connecting
> a local fix
> pkg-a: an upstream fix
> EOF
```

```scrut
$ git add vendor/pkg-a/file.txt && git commit --no-edit
[main a759598] Merge commit 'ed1183628db303e82765d92df3d655f05ba3b48c'
```

The merge commit contains the remote's side, so only the local fix is
left to push:

```scrut
$ git subtrees status vendor/pkg-a
ok   vendor/pkg-a -> $PLAYGROUND/upstream/pkg-a.git (push)
 file.txt | 1 +
 1 file changed, 1 insertion(+)
```

```scrut
$ git subtrees push
git push using:  vendor/pkg-a main
To $PLAYGROUND/upstream/pkg-a.git
   9f14d0d..eda413a  eda413a1e45e440ef23b5dfd4636a84831260a4f -> main
ok   vendor/pkg-a: pushed
```

```scrut
$ git subtrees status vendor/pkg-a
ok   vendor/pkg-a -> $PLAYGROUND/upstream/pkg-a.git (up to date)
```

If the two sides share no history at all, e.g. because the remote was
rebuilt from scratch, `merge`, `pull` and `push` don't try to merge. They
print the commands to keep either side instead; see the
[`diverged-unrelated-history`](../test/scenarios/diverged-unrelated-history/README.md)
scenario.
