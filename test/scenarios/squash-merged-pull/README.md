# Scenario: squash-merged-pull

A known bug: the remote's change was pulled on a feature branch, and the
feature branch was squash-merged into `main`. Since then, the tool
misreads `main`.

- **Monorepo (`vendor/a`)**: added at `seed` on `main`. On `feature`,
  `git subtree pull --squash` brought in `upstream change`. `feature` was
  squash-merged into `main` and deleted. Then a local commit on `main`
  added `local.txt`.
- **Remote**: `seed`, then `upstream change`. It has never seen
  `local.txt`.

Only the local side changed since `upstream change`, so the right state is
`push`. But the pull's squash commit, which records the sync point, was
only reachable through the pull's merge commit on `feature`. A squash
merge keeps the content and drops that history, so `main` still sees the
sync point from `git subtree add`. Measured against it, both sides changed.

## Output

`scenario_squash_merged_pull` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_squash_merged_pull
```
-->

`status` reports `diverged` instead of `push`:

```scrut
$ git subtrees status
ok   vendor/a -> $UPSTREAM (diverged)
 local.txt | 1 +
 1 file changed, 1 insertion(+)
```

`push` is rejected, since the history it rebuilds starts at the old sync
point:

```scrut
$ git subtrees push
git push using:  vendor/a main
To $UPSTREAM
 ! [rejected]        bd16e2c5cc3967a824b55916f9d66708a8fda514 -> main (non-fast-forward)
error: failed to push some refs to '$UPSTREAM'
hint: Updates were rejected because the tip of your current branch is behind
hint: its remote counterpart. If you want to integrate the remote changes,
hint: use 'git pull' before pushing again.
hint: See the 'Note about fast-forwards' in 'git push --help' for details.
!!   vendor/a: push failed
!!   Failed: vendor/a
[1]
```

`pull` recovers: it merges `upstream change` again, which changes no file,
and records a new sync point:

```scrut
$ git subtrees pull
ok   vendor/a fetched
Merge made by the 'ort' strategy.
ok   vendor/a: pulled
```

But the push after it rebuilds the squash-merged commit too, so the remote
gets `feature (squash-merged)`, which repeats `upstream change`, next to
the original:

```scrut
$ git subtrees push
git push using:  vendor/a main
To $UPSTREAM
   6045a98..90babaf  90babaf10d3e73b0251a158cb615b5c563b07c80 -> main
ok   vendor/a: pushed
```

```scrut
$ git -C "$UPSTREAM" log --graph --format='%s' main
*   Merge commit '00a22274fa7c6e2d9b734b9eefe569b3f8cdd6f8'
|\  
| * upstream change
* | local change
* | feature (squash-merged)
|/  
* seed
```
