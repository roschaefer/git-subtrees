# Feature branches

Every subtree syncs with the remote branch named like your current branch.
This walkthrough starts a feature branch in the [playground](README.md),
changes one subtree on it and pushes, and cleans up once the feature is
merged on both sides.

<!-- Builds a fresh playground; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

First, bring both subtrees up to date, as at the end of the
[main walkthrough](README.md#pull):

```scrut
$ git subtrees init vendor/pkg-b "$PLAYGROUND/upstream/pkg-b.git" >/dev/null && git subtrees pull >/dev/null
```

## A new branch

Neither remote has a `feature` branch.

```scrut
$ git switch -c feature
Switched to a new branch 'feature'
```

```scrut
$ git subtrees status
??   ghost -> (no mapping)
??   vendor/pkg-a -> $PLAYGROUND/upstream/pkg-a.git (no 'feature' branch on remote; monorepo base branch unknown -- pass --base <branch>)
??   vendor/pkg-b -> $PLAYGROUND/upstream/pkg-b.git (no 'feature' branch on remote; monorepo base branch unknown -- pass --base <branch>)
```

To tell whether a subtree changed on `feature`, git-subtrees compares it
with the branch `feature` was cut from. It looks for `--base`, then
`origin/HEAD`, then `init.defaultBranch`. The playground's monorepo was
never cloned, so it has no `origin/HEAD`:

```scrut
$ git config init.defaultBranch main
```

```scrut
$ git subtrees status
??   ghost -> (no mapping)
ok   vendor/pkg-a -> $PLAYGROUND/upstream/pkg-a.git (no 'feature' branch on remote; unchanged since 'main')
ok   vendor/pkg-b -> $PLAYGROUND/upstream/pkg-b.git (no 'feature' branch on remote; unchanged since 'main')
```

## Changing one subtree

```scrut
$ echo "a new option" >>vendor/pkg-b/file.txt && git commit -qam "pkg-b: add an option"
```

```scrut
$ git subtrees status
??   ghost -> (no mapping)
ok   vendor/pkg-a -> $PLAYGROUND/upstream/pkg-a.git (no 'feature' branch on remote; unchanged since 'main')
ok   vendor/pkg-b -> $PLAYGROUND/upstream/pkg-b.git (no 'feature' branch on remote; changed since 'main' -- push would create it)
 vendor/pkg-b/file.txt | 1 +
 1 file changed, 1 insertion(+)
```

With no remote branch to compare with, `diff` compares with `main`:

```scrut
$ git subtrees diff
===  vendor/pkg-b
diff --git a/file.txt b/file.txt
index b041961..b509b97 100644
--- a/file.txt
+++ b/file.txt
@@ -1 +1,2 @@
 pkg-b: seed
+a new option
```

`push` creates `feature` on `pkg-b`'s remote only. `pkg-a` didn't change,
so its remote doesn't get an empty branch.

```scrut
$ git subtrees push
ok   vendor/pkg-a: nothing to push (remote has no 'feature' branch; unchanged since 'main')
??   vendor/pkg-b: remote has no 'feature' branch yet -- this push will create it (changed since 'main')
git push using:  vendor/pkg-b feature
To $PLAYGROUND/upstream/pkg-b.git
 * [new branch]      87e88751a1a4981edb75ca754431364c649bbc00 -> feature
ok   vendor/pkg-b: pushed
```

```scrut
$ git subtrees status
??   ghost -> (no mapping)
ok   vendor/pkg-a -> $PLAYGROUND/upstream/pkg-a.git (no 'feature' branch on remote; unchanged since 'main')
ok   vendor/pkg-b -> $PLAYGROUND/upstream/pkg-b.git (up to date)
```

## After the merge

The feature gets merged on both sides: on `pkg-b`'s remote, which then
deletes the branch, and in the monorepo.

```scrut
$ git -C "$PLAYGROUND/upstream/pkg-b.git" push . feature:main
To .
   ceb784c..87e8875  feature -> main
```

```scrut
$ git -C "$PLAYGROUND/upstream/pkg-b.git" branch -D feature
Deleted branch feature (was 87e8875).
```

```scrut
$ git switch -q main && git merge --ff-only feature
Updating ef18234..1f18532
Fast-forward
 vendor/pkg-b/file.txt | 1 +
 1 file changed, 1 insertion(+)
```

Back on `main`, `pull` sees that the monorepo already has what the remote
merged, and `prune` removes the deleted branch's remote-tracking ref.

```scrut
$ git subtrees pull
ok   vendor/pkg-a fetched
ok   vendor/pkg-a: nothing to pull
ok   vendor/pkg-b fetched (main moved ceb784c..87e8875)
ok   vendor/pkg-b: nothing to pull
```

```scrut
$ git subtrees prune
Pruning vendor/pkg-b
URL: $PLAYGROUND/upstream/pkg-b.git
 * [pruned] vendor/pkg-b/feature
```

```scrut
$ git subtrees status
??   ghost -> (no mapping)
ok   vendor/pkg-a -> $PLAYGROUND/upstream/pkg-a.git (up to date)
ok   vendor/pkg-b -> $PLAYGROUND/upstream/pkg-b.git (up to date)
```
