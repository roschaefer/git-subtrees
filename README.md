# git-subtrees

> [!IMPORTANT]
> **This project is retired.** Use
> [git-splice](https://github.com/roschaefer/git-splice) instead.

git-subtrees managed the subtrees of a monorepo with `git subtree`: every
git remote named like a folder was that folder's repository. Building it
showed that this design is flawed at its root, in `git subtree` itself.
No amount of tooling on top fixes these three problems.

## 1. Remotes are not meant to be homes for subfolders

A subtree remote is an ordinary git remote. Git, your IDE and LazyGit all
treat it like any other remote, so any push that isn't a
`git subtree split` sends the **whole monorepo** there, including folders
that were never meant to leave it. A mistyped `git push vendor/foo main`
is enough, and so are `push.autoSetupRemote`, an upstream that points at
the subtree remote, or LazyGit suggesting the first remote. Deleting the
branch afterwards doesn't unpublish anything.

Every mitigation (a pre-push hook, a broken push URL, a custom remote
helper, server-side rules) has gaps, because it fights how git remotes
work. See [#50](https://github.com/roschaefer/git-subtrees/issues/50).

## 2. It does not scale

To find out whether a subtree has changes to push, `git subtree split`
walks every commit reachable from `HEAD`, a few milliseconds each, and has
no persistent cache. `status` and `push` get slower as the monorepo's
history grows: 8s at 550 commits, 44s at 5,500. The workarounds either
add commits to your history (`--rejoin`) that rebases and squash merges
lose again, or reimplement `git subtree split`. See
[#30](https://github.com/roschaefer/git-subtrees/issues/30).

## 3. The history is not linear

`git subtree add` and `pull` write merge commits into the monorepo, even
with `--squash`. If your `main` is kept linear (squash-merged pull
requests, rebased branches), those merges and the sync points they carry
get lost, or they clutter the history if you keep them. See
[Mastering Git subtrees](https://medium.com/@porteneuve/mastering-git-subtrees-943d29a798ec).

## What git-splice does differently

[git-splice](https://github.com/roschaefer/git-splice) keeps the goal:
edit other repositories as folders of your monorepo, test them together,
and sync both ways with plain Git. But:

- A committed `.splice` file in the folder records its repository and the
  last sync point. No subtree remote to push the monorepo to by mistake,
  and the sync point travels with your branches.
- A pull lands as one ordinary monorepo commit. Changes cross the splice,
  commits don't, so both repositories keep their own linear histories.

## The old documentation

The last release is
[v0.1.2](https://github.com/roschaefer/git-subtrees/tree/v0.1.2). Its
README documents every command.

## License

MIT, see [LICENSE](LICENSE).
