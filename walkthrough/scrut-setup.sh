# shellcheck shell=bash
# Sourced by the hidden first scrut block of each walkthrough in this
# folder; see `just docs-check`.
#
# Builds a fresh playground in the scrut work directory, like `just
# playground`, and cds into its monorepo. Dates are fixed and the
# developer's git config is ignored, so commit hashes are the same on
# every run.

PLAYGROUND="$PWD"
export PLAYGROUND
playground_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH="$(dirname "$playground_dir"):$playground_dir:$PATH"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z

"$playground_dir/setup.sh" --dir "$PLAYGROUND" --no-shell >/dev/null 2>&1 || return
unset playground_dir
cd "$PLAYGROUND/monorepo" || return

# The walkthroughs show what a terminal shows, stderr included, with the
# sandbox's random path as $PLAYGROUND, as `just playground` exports it.
# git subtree split's progress counter rewrites itself with \r; only what
# follows the last \r of a line stays.
git() {
  command git "$@" 2>&1 |
    sed -E "s#\r\$##; s#.*\r##; s#$PLAYGROUND#\$PLAYGROUND#g"
  return "${PIPESTATUS[0]}"
}
