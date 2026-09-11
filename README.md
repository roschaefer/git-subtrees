# git-subtrees

Manage multiple `git subtree` prefixes in a monorepo without a separate
config file.

## When to use this

You have a monorepo and want to fan parts of it out into their own repos
via `git subtree` — publishing a package, mirroring a library, keeping a
vendored copy in sync — and you don't want to hand-track which folder
maps to which remote across several subtrees.

## The contract

A subtree is any registered git remote whose name exactly matches the
path of an existing directory in the worktree:

    git remote add vendor/foo <url>

maps to the folder `vendor/foo`. That's the entire configuration -- there
is no config file. Run `git subtrees mapping` to see what's currently
discovered.

If you rename or move the folder, the remote no longer matches anything
until you also run `git remote rename <old-path> <new-path>`.

## Commands

    git subtrees mapping   # show every registered remote and what it maps to
    git subtrees fetch     # fetch all subtree remotes in parallel
    git subtrees status    # show which subtrees have local changes to push
    git subtrees push      # push subtrees with local changes to their remotes

Run `git subtrees <command> --help` for options.
