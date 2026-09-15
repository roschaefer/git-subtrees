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

    git subtrees status    # show every registered remote, what it maps to, and its sync state
    git subtrees fetch     # fetch all subtree remotes in parallel
    git subtrees pull      # bring in a subtree's remote changes (assumes already connected)
    git subtrees push      # push subtrees with local changes to their remotes
    git subtrees init      # one-time bootstrap of a single path/remote pair

Run `git subtrees <command> --help` for options.

`git subtrees pull` uses `git subtree pull --squash` rather than a plain merge:
squash mode's synthetic commit never drags in the remote's raw, unprefixed
history the way a non-squash pull would -- which matters, because that's
exactly what breaks `git subtree split`/`push` later with "tree entry is of
type blob, expected tree or commit" the moment it walks back through one of
those commits. This does mean each pull lands as one squashed commit rather
than the remote's individual commits -- the documented, standard trade-off
for subtrees pulled more than rarely. It's a no-op if you're already up to
date.

`pull` and `push` assume the subtree is already connected to its remote --
see the next section for the one-time step if it isn't yet.

### Sync states

`status`, `pull`, and `push` all classify each subtree's sync state the
same way, comparing what was last synced (recovered from `git subtree`'s
own `git-subtree-dir`/`git-subtree-split` commit trailers, not from
literal commit ancestry -- squash commits are never real ancestors of the
remote's raw history) against the current local and remote content:

- **`not-connected`** -- the remote has never been fetched.
- **`missing-at-head`** -- the remote doesn't have a branch matching your
  current branch name.
- **`up to date`** -- nothing to do.
- **`push`** / **`pull`** -- only one side moved since the last sync.
- **`diverged`** -- both sides moved, but they still share the sync point
  as a common ancestor. `pull` attempts its normal squash merge, which may
  hit an ordinary conflict -- resolve it and run plain `git commit`, then
  re-run `pull`.
- **`unrelated-history`** -- both sides moved (or never synced at all),
  and share **no** common ancestor -- typically because the remote's
  history was rebuilt from scratch independently of what this tool last
  knew about it. There's no principled automatic merge here, only a human
  decision to keep one side and discard the other's history, so `pull`
  and `push` don't attempt anything: they print two ready-to-run recovery
  commands, one to re-adopt the remote's version, one to force the local
  version onto the remote. See
  [`test/scenarios/diverged-unrelated-history/README.md`](test/scenarios/diverged-unrelated-history/README.md)
  for a concrete worked example.

## Bootstrapping a new subtree

Every other command in this tool is meant to be safe to run repeatedly without
thinking about it. The very first connection between a subtree and its remote isn't
-- it depends on which of a few situations you're in, and `git subtrees init
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
- **`git subtree add --prefix=<path> <url> <branch>`**, if `<path>` doesn't
  exist locally yet and the remote has independent history to bring in.
- **Tells you to move `<path>` aside yourself**, if `<path>` already has content that
  shares no common ancestor with the remote branch -- typically because something
  landed on the remote independently before you ever connected it (someone edited a
  file on GitHub, a bot's PR got merged, and so on). Reconciling unrelated local and
  remote content is a judgment call this tool won't make for you:

      mv <path> <path>.bak
      git subtrees init <path> <url>
      # then, e.g.: cp -rn <path>.bak/. <path>/ && git add <path> && git commit

## When not to use this

Two structural limitations, not bugs to fix:

- **No nested subtrees.** A subtree is identified purely by a remote name
  matching a directory path, and `git subtree` itself doesn't cleanly
  support one managed prefix living inside another. Two subtree paths must
  never be prefixes of one another (e.g. `vendor/pkg` and `vendor/pkg/extra`
  can't both be managed subtrees at once) -- a change under `vendor/pkg/extra`
  would be ambiguous about which subtree it belongs to, and `git subtree`'s
  own prefix-based diffing gets confused by overlapping prefixes. If you
  need one vendored project inside another, this tool isn't the right fit.
- **Same remote, multiple working directories.** A remote name maps 1:1 to
  exactly one directory, so this tool has no way to check the same
  upstream remote out into two different folders at once. Use `git
  worktree` instead -- that's precisely the problem it solves, and bending
  this tool's remote-to-path convention to cover it would reintroduce the
  kind of implicit shared state the zero-config design is meant to avoid.

## Install

    git clone <url> git-subtrees
    ln -s "$(pwd)/git-subtrees/git-subtrees" ~/.local/bin/git-subtrees

Make sure the symlink's target directory is on your `PATH` -- git picks
up any `git-<name>` executable on `PATH` as `git <name>`. The `lib/`
directory next to `git-subtrees` must stay alongside it; only the
top-level `git-subtrees` file gets symlinked.

Requires:

- Bash >= 4.2 (uses `mapfile` and `declare -g`). Linux distributions
  ship this by default; macOS's system bash is 3.2, so install a newer
  one (e.g. `brew install bash`) and make sure it's found first on
  `PATH`.
- The `git subtree` contrib command, bundled with git on most Linux
  distributions -- check with `git subtree --help`.

## Development

    nix develop

drops you into a shell with `git`, `bats`, `shellcheck`, `shfmt`, and
`just` on `PATH`, plus the repo's own `git-subtrees` (the live working
copy, not an installed one) prepended to `PATH` so `git subtrees ...`
immediately picks up uncommitted edits.

    just lint       # shellcheck
    just fmt-check  # shfmt -d
    just fmt        # shfmt -w
    just test       # bats --recursive test
    just ci         # lint + fmt-check + test, same as CI

Tests live under `test/`, one `*.bats` file per command plus `common.bats`
(discovery/classification) and `cli.bats` (real subprocess smoke tests
against the entrypoint, including through a symlink). `test/scenarios/`
holds named, self-documenting git-history fixtures -- each folder has a
`README.md` describing the exact history shape and a `setup.bash` building
it -- rather than ad hoc fixtures buried inside test files.

    playground/setup.sh

builds a throwaway sandbox (a scratch monorepo plus fixture bare "upstream"
repos, defaulting to a fresh `mktemp -d`) for manually exercising commands
against realistic state. Run it from inside `nix develop`; when run
interactively it prints a short walkthrough and drops you straight into a
shell inside the built monorepo -- `exit` to leave it. Pass `--no-shell` to
just print the sandbox path instead (the default when not run
interactively, e.g. piped or scripted).

    simulate-remote-change <path> [message]

also on `PATH` inside `nix develop`. Pushes one new commit to `<path>`'s
remote from outside the monorepo, so `git subtrees status`/`fetch`/`pull`
have real upstream activity to react to -- handy for repeating the
pull scenario on demand instead of only getting it once at playground
build time.

## License

MIT, see [LICENSE](LICENSE).
