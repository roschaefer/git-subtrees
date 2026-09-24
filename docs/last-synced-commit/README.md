# The "last synced commit"

`status`, `pull` and `push` all need to answer "what changed since this
subtree and its remote were last the same?". This page defines that point,
shows how it moves, and lists what it can't tell you.

Run the walkthrough to watch it happen in a scratch repo:

    docs/last-synced-commit/walkthrough.sh

Every state quoted below is what that script prints. `test/walkthrough.bats`
runs it, so this page can't drift from the code.

## Why it exists

`git subtree pull --squash` never makes the remote's commits ancestors of
your `HEAD`, so `git merge-base HEAD <remote>/<branch>` finds nothing. The
tool needs another anchor: a point in *your* history where `vendor/a` was
known to equal a specific upstream commit.

## Definition

Two commits, both found by looking backwards from `HEAD`
(`find_sync_commit` and `sync_split_sha` in `lib/common.sh`):

| Name | What it is | How it's found |
|---|---|---|
| **S**, the last synced commit | The squash commit `git subtree add`/`pull --squash` created. Its tree is exactly U's content, with no `vendor/a/` prefix. | Newest commit reachable from `HEAD` carrying a `git-subtree-dir: vendor/a` trailer. |
| **U**, the upstream commit taken | The remote commit whose content S recorded. | The `git-subtree-split: <sha>` trailer on S. |

```
                        U   (upstream commit, e.g. its main at the time)
                        │
   monorepo history:    S   "Squashed 'vendor/a/' content from commit U"
                         ╲   trailers: git-subtree-dir: vendor/a
                          ╲            git-subtree-split: U
   ── … ──────────────────── o ─────── a ─────── b ─────── HEAD
                            merge of S            local commits
                                                  under vendor/a
```

"Local changes" means `vendor/a` at `HEAD` differs from **S**'s tree.
The merge of S is not a usable baseline: when `pull` merges a divergence,
that merge already contains your unpushed local changes, and comparing
against it would hide them from `push`.
"Remote changes" means the remote branch's content differs from **U**.
Comparing those two answers gives the states in the README's *Sync states*
section (`push`, `pull`, `diverged`, ...).

## Properties worth knowing

1. **It lives in your history, not on the remote.** It exists whether or
   not the remote has a branch named like yours. But a missing remote
   branch takes away what to compare *with*, and the sync point can't
   replace that -- see the next section.
2. **It follows `HEAD`, not the branch name.** A branch cut from `main`
   inherits `main`'s sync point. Merging another branch in brings that
   branch's sync points along. Nothing compares `feature-1` to `feature-2`.
3. **`add`, `pull` and `push` move it.** Each writes a new squash commit.
   `push` writes it only after the remote accepted the push, so a rejected
   push leaves the sync point where it was. A push made with plain
   `git subtree push` instead of `git subtrees push` doesn't move it.
4. **It must come from a squash.** A plain `git subtree add` (no
   `--squash`) makes the sync commit itself the merge, so its tree is the
   whole monorepo rather than U's content.

## When the remote has no branch like yours

The sync point says what `vendor/a` looked like when it last matched
upstream. It can't say whether *this branch* changed anything, because it
is inherited from whatever branch you cut from.
So when the remote has no branch named like yours, the tool doesn't use it.
It compares inside the monorepo instead, with the **base branch**:

```
git diff $(git merge-base <base> HEAD) HEAD -- vendor/a
```

- **No difference:** the subtree is untouched on this branch. `push` skips
  it.
- **A difference:** the subtree changed on this branch. `push` creates the
  remote branch.

Using the merge base means changes that land on the base branch after you
cut yours don't count against you, and changes that were already on the base
branch when you cut it aren't yours either. Nothing on the remote is
consulted, and nothing depends on S or U, so it works the same for
subtrees added without `--squash` or adopted by plain commits.

Git doesn't record which branch you cut from. The base branch is `--base
<branch>` if given, else the target of `origin/HEAD`, else
`init.defaultBranch`; a candidate must exist and share history with `HEAD`.
If nothing resolves, the command asks for `--base` rather than guess. On the
base branch itself there is nothing to compare, and `push` creates the
missing branch.

Once the remote has the branch (for instance after `push` created it), this
case no longer applies: the normal same-name classification takes over.

## Walkthrough

Each row is one step of `walkthrough.sh`. "State" is what the tool
reports for the current branch.

| # | Step | Sync point | State | Why |
|---|---|---|---|---|
| 1 | `subtree add --squash` on `main` | S1 created | `up-to-date` | Local equals remote `main`. |
| 2 | Cut `feature-1`; remote has no such branch | S1 (inherited) | `missing-at-head`, **unchanged** vs base `main` | Nothing under `vendor/a` differs from the merge base with `main`, so `push` skips it. |
| 3 | Commit a change under `vendor/a` | S1 | `missing-at-head`, **changed** vs base `main` | `vendor/a` differs from the merge base, so `push` would create `feature-1`. |
| 4 | `git subtrees push` creates remote `feature-1` | **P1** | `up-to-date` | The remote branch exists now, so the same-name comparison applies, and it equals local. The push wrote sync point P1. |
| 5 | `feature-2` changes `vendor/a` too and is pushed; merge it into `feature-1` | **P2** (from `feature-2`) | `diverged` | The merge brought `feature-2`'s push P2, the newest sync point. P2 is on remote `feature-2`, not `feature-1`, so remote `feature-1` looks changed. See limitation 1. |
| 6 | Remote `feature-1` is deleted | P2 | `missing-at-head`, **changed** vs base `main` | Back to the base-branch case: `feature-1` still differs from `main`. |
| 7 | Upstream `main` moves; `git subtrees pull` on `main` | **S2** | `up-to-date` | `pull` wrote a new squash commit, so the sync point advanced. |
| 8 | Merge `main` into `feature-1` | S2 (inherited) | `missing-at-head`, **changed** vs base `main` | The merge brought S2 in. `feature-1` still has changes relative to the merge base with `main`. |

The walkthrough sets `init.defaultBranch` in its scratch repo, which is how
the base branch is found there.

## Known limitations

1. **The newest sync point may belong to another branch.** Sync points
   aren't tied to a remote branch, and the newest one wins (property 2).
   After merging a branch that was pushed to a remote branch of its own,
   the current branch's remote looks changed, and further local changes
   look `diverged`, although `push` fast-forwards it. Step 5.
2. **The base branch has to be findable.** With no `origin/HEAD`, no
   `init.defaultBranch` and no `--base`, `push` refuses on a branch the
   remote lacks. A monorepo whose own remote isn't called `origin` gets no
   help from `origin/HEAD`.
3. **A new remote branch isn't checked against the remote's history.**
   When `push` creates a branch for a subtree that changed, it sends the
   subtree's split history. For a subtree that was never added through
   `git subtree`, that history shares nothing with the remote's other
   branches.
4. **Stacked branches compare with the base, not their parent.** A branch
   cut from `feature-1` (not from the base branch) counts everything
   `feature-1` changed as its own, unless you pass `--base feature-1`.

This page documents what the tool does now.
