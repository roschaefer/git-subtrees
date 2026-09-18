#!/usr/bin/env bash
# Builds a throwaway monorepo + upstream and walks through the "last synced
# commit" concept step by step, printing what git-subtrees sees after each
# step. See README.md in this directory for what every step means.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: docs/last-synced-commit/walkthrough.sh [--dir <path>]

Runs the walkthrough in a scratch directory (a fresh mktemp -d, or <path>)
and prints the sync state after every step. Nothing outside that directory
is touched.
EOF
}

dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      dir="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/common.sh
source "$root/lib/common.sh"

if [[ -z "$dir" ]]; then
  dir="$(mktemp -d "${TMPDIR:-/tmp}/git-subtrees-walkthrough.XXXXXX")"
fi
mkdir -p "$dir"
upstream="$dir/upstream.git"
mono="$dir/monorepo"

export GIT_AUTHOR_NAME=Walkthrough GIT_AUTHOR_EMAIL=walkthrough@example.com
export GIT_COMMITTER_NAME=Walkthrough GIT_COMMITTER_EMAIL=walkthrough@example.com

step() { printf '\n=== %s\n' "$*"; }
# Echoes the command, then runs it quietly.
run() {
  printf '$ %s\n' "$*"
  "$@" >/dev/null 2>&1
}

short_subject() { git log -1 --format='%h %s' "$1"; }

# Prints the sync point as seen from HEAD, then the classification against
# the remote branch named like the current branch (or, when the remote has
# none, against its default branch).
show_state() {
  local path="vendor/a" branch sync split merge
  branch="$(current_branch)"
  sync="$(find_sync_commit "$path")"
  split="$(sync_split_sha "$sync")"
  merge="$(find_merge_commit_for_sync "$sync")"
  printf '  branch:                 %s\n' "$branch"
  printf '  last synced (S):        %s\n' "$(short_subject "$sync")"
  printf '  upstream commit taken:  %s\n' "${split:0:7}"
  printf '  local-change baseline:  %s\n' "$(short_subject "${merge:-$sync}")"
  classify_subtree "$path" "$branch"
  if [[ -n "$SUBTREE_BASELINE_BRANCH" ]]; then
    printf "  => %s (vs default branch '%s')\n" "$SUBTREE_STATE" "$SUBTREE_BASELINE_BRANCH"
  else
    printf '  => %s\n' "$SUBTREE_STATE"
  fi
}

# Adds one commit to the upstream's main, the way a remote collaborator would.
upstream_commit() {
  local tmp
  tmp="$(mktemp -d)"
  git clone -q "$upstream" "$tmp" 2>/dev/null
  (
    cd "$tmp"
    git checkout -q -B main
    echo "$1" >>file.txt
    git add file.txt
    git commit -q -m "$1"
    git push -q origin main
  )
  rm -rf "$tmp"
}

git init -q --bare -b main "$upstream"
upstream_commit "upstream: seed"
git init -q -b main "$mono"
cd "$mono"
git commit -q --allow-empty -m "monorepo: initial commit"

step "1. Add the subtree (git subtree add --squash) on main"
run git remote add vendor/a "$upstream"
run git fetch vendor/a
run git subtree add --prefix=vendor/a vendor/a main --squash
show_state

step "2. Cut feature-1 from main; the remote has no feature-1"
run git checkout -b feature-1
show_state

step "3. Change something under vendor/a on feature-1"
echo one >vendor/a/one.txt
run git add vendor/a/one.txt
run git commit -m "feature-1: change vendor/a"
show_state

step "4. Push it (git subtree push) -- remote feature-1 now exists"
run git subtree push --prefix=vendor/a vendor/a feature-1
run git fetch vendor/a
show_state

step "5. feature-2 changes vendor/a too and is pushed; merge it into feature-1"
run git checkout -b feature-2 main
echo two >vendor/a/two.txt
run git add vendor/a/two.txt
run git commit -m "feature-2: change vendor/a"
run git subtree push --prefix=vendor/a vendor/a feature-2
run git checkout feature-1
run git merge --no-edit feature-2
run git fetch vendor/a
show_state

step "6. The remote's feature-1 is deleted (e.g. merged upstream, branch removed)"
run git push vendor/a --delete feature-1
run git fetch --prune vendor/a
show_state

step "7. Upstream main moves; 'git subtrees pull' on main creates a new sync point"
upstream_commit "upstream: second change"
run git checkout main
run "$root/git-subtrees" pull vendor/a
show_state

step "8. Merge main into feature-1 -- feature-1 inherits the newer sync point"
run git checkout feature-1
run git merge --no-edit main
show_state

printf '\nScratch repo left at %s\n' "$mono"
