# shellcheck shell=bash
# Sourced by the hidden first scrut block of each scenario's README.md; see
# `just docs-check`.
#
# Builds the scenario of the README's folder with its setup.bash, the same
# function the bats tests use, and cds into its monorepo. The remote is a
# bare repository at $UPSTREAM. Dates are fixed and the developer's git
# config is ignored, so commit hashes are the same on every run.

scenarios_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH="$(cd "$scenarios_dir/../.." && pwd):$PATH"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z
UPSTREAM="$PWD/upstream"
export UPSTREAM

# shellcheck source=test/helpers/fixtures.bash
source "$scenarios_dir/../helpers/fixtures.bash"
# shellcheck disable=SC1091
source "$TESTDIR/setup.bash"
scenario_name="$(basename "$TESTDIR")"
"scenario_${scenario_name//-/_}" "$PWD/monorepo" "$UPSTREAM" >/dev/null 2>&1 || return
unset scenarios_dir scenario_name
cd monorepo || return

# The READMEs show what a terminal shows, stderr included, with the
# remote's path as $UPSTREAM. git subtree split's progress counter
# rewrites itself with \r; only what follows the last \r of a line stays.
git() {
  command git "$@" 2>&1 |
    sed -E "s#\r\$##; s#.*\r##; s#$UPSTREAM#\$UPSTREAM#g"
  return "${PIPESTATUS[0]}"
}
