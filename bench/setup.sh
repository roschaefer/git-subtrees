#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: bench/setup.sh <dir>

Builds a synthetic monorepo for bench/run.sh in <dir>/monorepo: subtrees
packages/sub1, packages/sub2, ..., each with local commits since it was
added. Halfway through, every subtree was pushed, so each remote holds the
monorepo's own push and the monorepo has changed since -- the usual state
after working on a branch for a while.

Every remote is reached through git's ext:: transport with a delay per
connection, so network round trips cost something, as they do over SSH.
With plain local remotes, fetching would look free.

Environment (defaults in brackets):
  BENCH_SUBTREES  number of subtrees [10]
  BENCH_COMMITS   local commits per subtree since it was added [50]
  BENCH_LATENCY   seconds of delay per remote connection [0.2]
EOF
}

[[ "${1:-}" == -h || "${1:-}" == --help ]] && {
  usage
  exit 0
}
[[ $# -eq 1 && "$1" != -* ]] || {
  usage >&2
  exit 1
}

dir="$1"
subtrees="${BENCH_SUBTREES:-10}"
commits="${BENCH_COMMITS:-50}"
latency="${BENCH_LATENCY:-0.2}"

# The fixture must not depend on, or be slowed down by, the user's config.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Bench GIT_AUTHOR_EMAIL=bench@example.com
export GIT_COMMITTER_NAME=Bench GIT_COMMITTER_EMAIL=bench@example.com

rm -rf "$dir"
mkdir -p "$dir/upstream"
dir="$(cd "$dir" && pwd)"

git init -q -b main "$dir/monorepo"
cd "$dir/monorepo"
git config protocol.ext.allow always
git commit -q --allow-empty -m "initial commit"

for ((i = 1; i <= subtrees; i++)); do
  upstream="$dir/upstream/sub$i.git"
  git init -q --bare -b main "$upstream"
  seed="$(mktemp -d)"
  git -C "$seed" init -q -b main
  echo "sub$i" >"$seed/README"
  git -C "$seed" add README
  git -C "$seed" commit -q -m "seed sub$i"
  git -C "$seed" push -q "$upstream" main
  rm -rf "$seed"

  git remote add "packages/sub$i" "ext::sh -c sleep% $latency;% exec% %S% $upstream"
  git fetch -q "packages/sub$i" 2>/dev/null
  git subtree add -q --prefix="packages/sub$i" "packages/sub$i" main --squash >/dev/null 2>&1
done

# One commit per subtree per round, plus unrelated work in between, so the
# history since each sync interleaves all subtrees like a real monorepo.
commit_round() {
  local round="$1" i
  for ((i = 1; i <= subtrees; i++)); do
    echo "round $round" >>"packages/sub$i/README"
    git add "packages/sub$i/README"
    git commit -q -m "sub$i: round $round"
  done
  echo "round $round" >>app.txt
  git add app.txt
  git commit -q -m "app: round $round"
}

for ((round = 1; round <= commits / 2; round++)); do
  commit_round "$round"
done
for ((i = 1; i <= subtrees; i++)); do
  git subtree push -q --prefix="packages/sub$i" "packages/sub$i" main >/dev/null 2>&1
done
git fetch -q --all
for ((round = commits / 2 + 1; round <= commits; round++)); do
  commit_round "$round"
done
