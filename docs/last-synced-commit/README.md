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

Three commits, all found by looking backwards from `HEAD`
(`find_sync_commit`, `sync_split_sha`, `find_merge_commit_for_sync` in
`lib/common.sh`):

| Name | What it is | How it's found |
|---|---|---|
| **S**, the last synced commit | The squash commit `git subtree add`/`pull --squash` created. Its tree has no `vendor/a/` prefix. | Newest commit reachable from `HEAD` carrying a `git-subtree-dir: vendor/a` trailer. |
| **U**, the upstream commit taken | The remote commit whose content S recorded. | The `git-subtree-split: <sha>` trailer on S. |
| **M**, the local-change baseline | The merge commit that brought S into your history. `vendor/a` in M is exactly U's content. | The commit after S on the path to `HEAD` whose parents include S. |

```
                        U   (upstream commit, e.g. its main at the time)
                        │
   monorepo history:    S   "Squashed 'vendor/a/' content from commit U"
                         ╲   trailers: git-subtree-dir: vendor/a
                          ╲            git-subtree-split: U
   ── … ──────────────────── M ─────── a ─────── b ─────── HEAD
                            merge of S            local commits
                                                  under vendor/a
```

"Local changes" means `vendor/a` differs between **M** and `HEAD`.
"Remote changes" means the remote branch's content differs from **U**.
Comparing those two answers gives the states in the README's *Sync states*
section (`push`, `pull`, `diverged`, ...).

## Properties worth knowing

1. **It lives in your history, not on the remote.** It exists whether or
   not the remote has a branch named like yours. What a missing branch
   takes away is the *target* to compare with, so the tool falls back to
   the remote's default branch (`main`, or `subtrees.defaultBranch`) as a
   read-only baseline -- see below.
2. **It follows `HEAD`, not the branch name.** A branch cut from `main`
   inherits `main`'s sync point. Merging another branch in brings that
   branch's sync points along. Nothing compares `feature-1` to `feature-2`.
3. **Only `add` and `pull` move it.** Each writes a new squash commit.
   `push` writes nothing into your history, so pushing never advances it.
4. **It must come from a squash.** A plain `git subtree add` (no
   `--squash`) makes the sync commit itself the merge, so there is no
   separate **M** to diff against.

## When the remote has no branch like yours

The target of the comparison is normally the remote branch named like your
current branch. If it doesn't exist, the target becomes the remote's
default branch and the state is reported "vs default branch". Everything
else -- S, U, M -- stays the same, and `classify_subtree` runs unchanged
against the new target:

- nothing under `vendor/a` differs from the default branch: `up-to-date`
  (or `pull`, if the default branch moved on) -- `push` skips it;
- something differs: `push` (or `diverged`) -- `push` creates your branch;
- no squash sync point at all: `unrelated-history` -- `push` refuses and
  prints recovery commands;
- the remote has neither branch: `missing-at-head` -- `push` refuses,
  because the contract's default branch is missing.

## Walkthrough

Each row is one step of `walkthrough.sh`. "State" is what
`classify_subtree` reports against the remote branch named like the
current branch.

| # | Step | Sync point | State | Why |
|---|---|---|---|---|
| 1 | `subtree add --squash` on `main` | S1 / M1 created | `up-to-date` | Local equals remote `main`. |
| 2 | Cut `feature-1`; remote has no such branch | S1 / M1 (inherited) | `up-to-date` (vs default branch `main`) | Nothing under `vendor/a` differs from `main`, so `push` skips it. |
| 3 | Commit a change under `vendor/a` | S1 / M1 | `push` (vs default branch `main`) | `vendor/a` has something `main` lacks, so `push` would create `feature-1`. |
| 4 | `subtree push` creates remote `feature-1` | S1 / M1 (unchanged) | `up-to-date` | The remote branch exists now and equals local. Note the sync point did not move. |
| 5 | Another branch changes `vendor/a` too; merge it into `feature-1` | S1 / M1 | `diverged` | See limitation 1. |
| 6 | Remote `feature-1` is deleted | S1 / M1 | `push` (vs default branch `main`) | Back to comparing with `main`: local has extra content, `main` hasn't moved. Everything pushed earlier is no longer "new" relative to the remote. |
| 7 | Upstream `main` moves; `git subtrees pull` on `main` | **S2 / M2** | `up-to-date` | `pull` wrote a new squash commit, so the sync point advanced. |
| 8 | Merge `main` into `feature-1` | S2 / M2 (inherited) | `push` (vs default branch `main`) | The merge brought S2 in. `feature-1` still has content `main` lacks. |

## Known limitations

These are consequences of property 3 (only `add` and `pull` move the sync
point). They are real behaviour today, not design goals.

1. **After a push, further local changes look `diverged`.** The remote
   branch now differs from U (because *you* pushed to it), and local
   differs from M, so the tool sees two-sided change. It can't tell the
   remote's change was your own push. Step 5.
2. **`pull` ignores the baseline.** It still fetches your current branch
   and fails when the remote lacks it, so on a feature branch that no
   remote has yet, `status` can show `pull` against `main` while `pull`
   itself cannot act on it.
3. **The default branch is an assumption.** A remote without it (or with
   it under another name and no `subtrees.defaultBranch`) is `missing-at-head`,
   and `push` refuses there rather than guess.

Treating a successful push as a sync point would fix limitation 1. Neither
that nor a baseline-aware `pull` is implemented; this page documents what
the tool does now.
