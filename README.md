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
is no config file. Run `git subtrees status` to see what's currently
discovered.

If you rename or move the folder, the remote no longer matches anything
until you also run `git remote rename <old-path> <new-path>`.

The second (and only other) assumption: **your current local branch name is
assumed to match the branch name on every subtree remote.** `fetch`/`status`/
`pull`/`push` all compare against and act on `refs/remotes/<remote>/<branch>`
where `<branch>` is whatever `git symbolic-ref --short HEAD` reports right
now -- there's no separate `--base`/tracking-branch configuration, and no
fallback to `main` if a same-named branch doesn't exist on a remote yet (in
that case the command just reports there's nothing to compare against). In
practice this means: work on `main` locally to sync against each remote's
`main`, or check out a feature branch locally to fan the same-named feature
branch out across every subtree remote it touches -- either way, name your
local branch the same as you want it to be everywhere.

## Commands

    git subtrees pull      # bring in a subtree's remote changes (assumes already connected)
    git subtrees status    # show every registered remote, what it maps to, and its connection state
    git subtrees fetch     # fetch all subtree remotes in parallel
    git subtrees push      # push subtrees with local changes to their remotes
    git subtrees connect   # one-time bootstrap of a single path/remote pair

Run `git subtrees <command> --help` for options.

`git subtrees pull` uses `git subtree pull --squash` rather than a plain merge:
squash mode's synthetic commit is parented on your own previous pull, never on the
remote's raw commit, so repeated pulls can't drag in the remote's unprefixed history
the way a non-squash pull would -- which matters, because that's exactly what breaks
`git subtree split`/`push` later with "tree entry is of type blob, expected tree or
commit" the moment it walks back through one of those commits. This does mean each
pull lands as one squashed commit rather than the remote's individual commits -- the
documented, standard trade-off for subtrees pulled more than rarely. It's a no-op if
you're already up to date.

`pull` assumes the subtree is already connected to its remote -- see the next section
for the one-time step if it isn't yet.

## Bootstrapping a new subtree

Every other command in this tool is meant to be safe to run repeatedly without
thinking about it. The very first connection between a subtree and its remote isn't
-- it depends on which of a few situations you're in, and `git subtrees connect
<path> <url>` figures it out on its own.

If no remote named `<path>` exists yet, it registers one pointing at `<url>`
(equivalent to `git remote add <path> <url>`). If one already exists but points
somewhere else, it refuses and tells you to fix it -- it never rewrites an
existing remote's URL (`git remote set-url`, and check for a leftover `--push`
override, are the manual fix).

Then, based on local and remote state, it does exactly one of:

- **Nothing**, if the remote has no matching branch yet -- there's nothing to connect,
  your next `git subtrees push <path>` will populate it.
- **Nothing**, if `<path>` already has content and is already connected.
- **`git subtree add --prefix=<path> <url> <branch>`**, if `<path>` is empty or
  doesn't exist yet and the remote has independent history to bring in. (`add`
  requires `<path>` not already exist locally -- an empty directory there gets
  removed first, since that satisfies `add`'s check without losing anything.)
- **Tells you to move `<path>` aside yourself**, if `<path>` already has content that
  shares no common ancestor with the remote branch -- typically because something
  landed on the remote independently before you ever connected it (someone edited a
  file on GitHub, a bot's PR got merged, and so on). Reconciling unrelated local and
  remote content is a judgment call this tool won't make for you:

      mv <path> <path>.bak
      git subtrees connect <path> <url>
      # then, e.g.: cp -rn <path>.bak/. <path>/ && git add <path> && git commit

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
