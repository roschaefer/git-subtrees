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
      if [[ $# -lt 2 ]]; then
        echo "--dir needs a path" >&2
        usage >&2
        exit 1
      fi
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

# Ignore the developer's own git config (signing, hooks templates, ...), so
# the walkthrough behaves the same on every machine.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Walkthrough GIT_AUTHOR_EMAIL=walkthrough@example.com
export GIT_COMMITTER_NAME=Walkthrough GIT_COMMITTER_EMAIL=walkthrough@example.com

step() { printf '\n=== %s\n' "$*"; }
# A fake clock, one minute per command: which sync point is the newest
# decides the state, so commits must not share a timestamp.
clock=1700000000
tick() {
  clock=$((clock + 60))
  export GIT_AUTHOR_DATE="@$clock +0000" GIT_COMMITTER_DATE="@$clock +0000"
}
# Echoes the command, then runs it quietly.
run() {
  printf '$ %s\n' "$*"
  tick
  "$@" >/dev/null 2>&1
}

short_subject() { git log -1 --format='%h %s' "$1"; }

# Prints the sync point as seen from HEAD, then the classification against
# the remote branch named like the current branch. If the remote has none,
# whether the subtree changed on this branch compared with the monorepo's
# base branch (main, via init.defaultBranch below).
show_state() {
  local path="vendor/a" branch sync split
  branch="$(current_branch)"
  sync="$(find_sync_commit "$path")"
  split="$(sync_split_sha "$sync")"
  printf '  branch:                 %s\n' "$branch"
  printf '  last synced (S):        %s\n' "$(short_subject "$sync")"
  printf '  upstream commit taken:  %s\n' "${split:0:7}"
  classify_subtree "$path" "$branch"
  if [[ "$SUBTREE_STATE" == "missing-at-head" ]]; then
    changes_vs_base "$path"
    case "$SUBTREE_CHANGES_VS_BASE" in
      yes) printf "  => missing-at-head (changed vs base '%s')\n" "$SUBTREE_BASE_BRANCH" ;;
      no) printf "  => missing-at-head (unchanged vs base '%s')\n" "$SUBTREE_BASE_BRANCH" ;;
      *) printf '  => missing-at-head (%s)\n' "$SUBTREE_CHANGES_VS_BASE" ;;
    esac
  else
    printf '  => %s\n' "$SUBTREE_STATE"
  fi
}

# Adds one commit to the upstream's main, the way a remote collaborator would.
upstream_commit() {
  local tmp
  tick
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
# What most setups have: how git-subtrees learns which branch is the base.
git config init.defaultBranch main
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
run "$root/git-subtrees" push vendor/a
run git fetch vendor/a
show_state

step "5. feature-2 changes vendor/a too and is pushed; merge it into feature-1"
run git checkout -b feature-2 main
echo two >vendor/a/two.txt
run git add vendor/a/two.txt
run git commit -m "feature-2: change vendor/a"
run "$root/git-subtrees" push vendor/a
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
