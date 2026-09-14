# This is another test

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

## Install

    git clone <url> git-subtrees
    ln -s "$(pwd)/git-subtrees/git-subtrees" ~/.local/bin/git-subtrees

Make sure the symlink's target directory is on your `PATH` -- git picks
up any `git-<name>` executable on `PATH` as `git <name>`.

Requires:

- Bash >= 4.2 (uses `mapfile` and `declare -g`). Linux distributions
  ship this by default; macOS's system bash is 3.2, so install a newer
  one (e.g. `brew install bash`) and make sure it's found first on
  `PATH`.
- The `git subtree` contrib command, bundled with git on most Linux
  distributions -- check with `git subtree --help`.

## License

MIT, see [LICENSE](LICENSE).
