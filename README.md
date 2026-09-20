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

Assumption one: **the remote name is the subtree path.** If you rename or
move the folder, the remote no longer matches anything until you also run
`git remote rename <old-path> <new-path>`.

Assumption two: **the local branch name is the remote branch name.**
`fetch`/`status`/`pull`/`push` use your current branch for every subtree
remote. Work on `main` to sync with remote `main`; check out a feature
branch to sync with that same feature branch on each touched remote.

### Feature branches that a remote doesn't have yet

On a branch the subtree's remote has no counterpart for -- typically a
fresh feature branch -- there is nothing to compare with. `status` and
`push` then ask a question about the monorepo instead: did the subtree
change **on this branch**, compared with the monorepo's *base branch* (the
branch this one was cut from)? `push` creates the remote branch only if it
did, so working on a feature branch doesn't spawn empty branches on every
remote. Nothing on the remote is consulted, and changes that were already on
the base branch, or that landed there after you cut yours, don't count.

Git doesn't record which branch you cut from, so the base branch is taken
from, in order: `--base <branch>` on `status`/`push`, the target of the
monorepo's `origin/HEAD`, then `git config init.defaultBranch`. If none of
those names an existing branch that shares history with `HEAD`, the command
says so and asks for `--base`; it never guesses. This only applies while the
remote lacks the branch: once `push` has created it, the usual same-name
comparison takes over.

## Commands

    git subtrees diff      # show the committed file changes that push would send
    git subtrees status    # show every registered remote, what it maps to, and its sync state
    git subtrees fetch     # fetch all subtree remotes in parallel
    git subtrees pull      # bring in remote changes with a squash merge
    git subtrees prune     # prune stale remote-tracking refs for subtree remotes
    git subtrees push      # push subtrees with local changes to their remotes
    git subtrees init      # one-time bootstrap of a single path/remote pair

Run `git subtrees <command> --help` for options.

### Mental model: Git versus git-subtrees

Each `git subtrees` command applies the familiar Git operation across the
discovered subtree repositories, using the current monorepo branch as the
branch name in each remote:

| Git command | What Git acts on | `git subtrees` counterpart | What this tool acts on |
| --- | --- | --- | --- |
| `git status` | Summarizes the **current worktree and branch**. | `git subtrees status` | Summarizes the sync state of **every selected subtree and its remote branch**. |
| `git diff` | Shows worktree changes that could be **committed**. | `git subtrees diff` | Shows committed subtree changes that would be **pushed**. |
| `git fetch` | Updates remote-tracking refs from **one remote**. | `git subtrees fetch` | Updates remote-tracking refs from **every selected subtree remote**. |
| `git pull` | Integrates remote changes into the **current repository**. | `git subtrees pull` | Squash-merges remote changes into **every selected subtree directory**. |
| `git push` | Pushes the **current repository's refs** to a remote. | `git subtrees push` | Splits and pushes **every selected locally changed subtree** to its matching remote. |
| `git remote prune` | Removes stale tracking refs for **one remote**. | `git subtrees prune` | Removes stale tracking refs for **every selected subtree remote**. |
| `git init` | Initializes the **current directory** as a Git repository. | `git subtrees init` | Initializes **one path/remote pair inside the monorepo** as a managed subtree. |

`diff`, like `status`, is purely local and uses the last fetched remote refs.
Run `git subtrees fetch` first when the comparison must reflect the latest
remote state. It compares committed content at `HEAD`; uncommitted worktree
changes are not included because `git subtree push` cannot send them. When
writing to a terminal, its output uses Git's pager configuration (including
`pager.subtrees`); `git --no-pager subtrees diff` disables paging as usual.

`pull` always performs a squash merge. It fetches the selected subtree branch
explicitly, then merges the fetched tracking ref without refetching during the
serial merge phase. If that branch fetch fails (for example because the
upstream branch was deleted), `pull` fails too, matching the failure shape of
plain `git subtree pull <remote> <branch>`.

`prune` delegates to `git remote prune` for each selected subtree remote. It
follows the remote's configured fetch refspecs, so explicit non-branch mappings
such as tags can be pruned too. Use `git subtrees prune --dry-run` to inspect
what Git would delete first.

### Sync states

`status`, `pull`, and `push` all classify each subtree's sync state the
same way, comparing what was last synced (recovered from `git subtree`'s
own `git-subtree-dir`/`git-subtree-split` commit trailers, not from
literal commit ancestry -- squash commits are never real ancestors of the
remote's raw history) against the current local and remote content:

- **never fetched** -- the remote has no tracking refs yet.
- **`missing-at-head`** -- the remote doesn't have a branch matching your
  current branch name. `status` then reports whether the subtree changed
  since the monorepo's base branch, and `push` creates the branch only if it
  did (see *Feature branches that a remote doesn't have yet*).
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

Use `git subtrees init <path> <url>` for the one-time add/adopt step.

If no remote named `<path>` exists yet, it registers one pointing at `<url>`
(equivalent to `git remote add <path> <url>`). If one already exists but points
somewhere else, it refuses and tells you to fix it -- it never rewrites an
existing remote's URL.

Then, based on local and remote state, it does exactly one of:

- **Nothing**, if the remote has no matching branch yet -- your first
  `git subtrees push <path>` can create it.
- **Nothing**, if `<path>` already has subtree history.
- **`git subtree add --prefix=<path> <url> <branch>`**, if `<path>` doesn't
  exist locally yet and the remote has independent history to bring in.
- **Tells you to move `<path>` aside yourself**, if `<path>` already has content that
  shares no common ancestor with the remote branch. Reconciling unrelated local and
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

Without cloning the full repo, download the `edge` release instead --
a tarball rebuilt on every push to `main`, so it always tracks the
latest commit rather than a specific version:

    mkdir -p ~/.local/share ~/.local/bin
    curl -fL https://github.com/roschaefer/git-subtrees/releases/download/edge/git-subtrees-edge.tar.gz \
      | tar -xz -C ~/.local/share
    ln -s ~/.local/share/git-subtrees/git-subtrees ~/.local/bin/git-subtrees

Requires:

- Bash >= 4.4. Modern Linux distributions ship this by default; macOS's
  system bash is 3.2, so install a newer one (e.g. `brew install bash`)
  and make sure it's found first on `PATH`.
- The `git subtree` contrib command, bundled with git on most Linux
  distributions -- check with `git subtree --help`.

### Shell completions

Completions for bash, zsh, and fish live under `completions/`. They
complete both `git subtrees <TAB>` and the standalone `git-subtrees <TAB>`,
and offer discovered subtree paths as arguments to `diff`/`fetch`/`pull`/
`prune`/`push`/`status`.

    # bash -- source from ~/.bashrc, or drop into a directory bash-completion
    # loads eagerly (e.g. /etc/bash_completion.d/), since git's own dispatch
    # to _git_subtrees needs the function already defined in the shell
    source /path/to/git-subtrees/completions/git-subtrees.bash

    # zsh -- install as `_git-subtrees` on your $fpath, then start a new
    # shell (or run `compinit`)
    ln -s /path/to/git-subtrees/completions/git-subtrees.zsh \
      /usr/local/share/zsh/site-functions/_git-subtrees

    # fish
    ln -s /path/to/git-subtrees/completions/git-subtrees.fish \
      ~/.config/fish/completions/git-subtrees.fish

## Development

    nix develop

drops you into a shell with all development tools and the live
`git-subtrees` entrypoint on `PATH`.

    just lint       # shellcheck
    just fmt-check  # shfmt -d
    just fmt        # shfmt -w
    just test       # bats --recursive test
    just ci         # lint + fmt-check + test, same as CI

Tests live under `test/`; scenario fixtures live under `test/scenarios/`.

    playground/setup.sh

builds a throwaway monorepo plus fixture upstream repos for manual testing.
Run it inside `nix develop`; pass `--no-shell` to print the sandbox path
without entering a shell.

    simulate-remote-change <path> [message]

also on `PATH` inside `nix develop`, pushes one new upstream commit so you
can repeat a pull scenario on demand.

## License

MIT, see [LICENSE](LICENSE).
