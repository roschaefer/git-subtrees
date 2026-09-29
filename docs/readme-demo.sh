#!/usr/bin/env bash
# Runs the README's example session against this checkout and compares the
# output with the README, or writes it there with --write.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: docs/readme-demo.sh [--write]

Builds a monorepo with three subtrees in a scratch directory -- ui changed
upstream, api changed locally, lib in sync -- runs fetch, status, pull and
push with this checkout's git-subtrees, and compares the output with the
block between the demo markers in README.md.

Author, committer and dates are fixed, so commit hashes are the same on
every run. Scratch paths are shown as https://github.com/acme/<name>.git.

  --write   replace the README block instead of comparing
EOF
}

write=0
case "${1:-}" in
  "") ;;
  --write) write=1 ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

root="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
readme="$root/README.md"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export PATH="$root:$PATH"
export GIT_CONFIG_GLOBAL="$tmp/gitconfig" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=demo GIT_AUTHOR_EMAIL=demo@example.com
export GIT_COMMITTER_NAME=demo GIT_COMMITTER_EMAIL=demo@example.com
export GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z
git config --global init.defaultBranch main

build_scenario() {
  local repo
  for repo in api lib ui; do
    git init -q --bare "$tmp/up/$repo.git"
    git clone -q "$tmp/up/$repo.git" "$tmp/seed-$repo" 2>/dev/null
    echo "$repo v1" >"$tmp/seed-$repo/README.md"
    git -C "$tmp/seed-$repo" add README.md
    git -C "$tmp/seed-$repo" commit -q -m "$repo: first"
    git -C "$tmp/seed-$repo" push -q origin main
  done

  git init -q "$tmp/mono"
  cd "$tmp/mono"
  git commit -q --allow-empty -m initial
  git subtrees init packages/api "$tmp/up/api.git" >/dev/null 2>&1
  git subtrees init packages/ui "$tmp/up/ui.git" >/dev/null 2>&1
  git subtrees init vendor/lib "$tmp/up/lib.git" >/dev/null 2>&1

  echo "ui v2" >>"$tmp/seed-ui/README.md"
  git -C "$tmp/seed-ui" commit -q -am "ui: new button"
  git -C "$tmp/seed-ui" push -q origin main

  echo "api v2" >>packages/api/README.md
  git add packages/api
  git commit -q -m "api: add endpoint"
}

# Prints each command and its output, indented as a Markdown code block.
# git subtree split's progress counter rewrites itself with \r in a
# terminal; only what follows the last \r of a line stays.
session() {
  local cmd
  for cmd in "git remote" "git subtrees fetch" "git subtrees status" \
    "git subtrees pull" "git subtrees push"; do
    [[ "$cmd" == "git remote" ]] || echo
    echo "\$ $cmd"
    $cmd 2>&1
  done | sed -E "s#\r\$##; s#.*\r##; s#$tmp/up/([a-z]+)\.git#https://github.com/acme/\1.git#g; s#^#    #; s#^ +\$##"
}

# Without both markers, the block would be silently left alone.
for marker in '<!-- demo:start -->' '<!-- demo:end -->'; do
  if [[ "$(grep -cxF -- "$marker" "$readme" || true)" != 1 ]]; then
    echo "README.md needs exactly one line '$marker'" >&2
    exit 1
  fi
done

build_scenario
block="$(session)"

# The README with the block between the markers replaced.
expected="$(
  awk -v block="$block" '
    /^<!-- demo:start -->$/ { print; print ""; print block; print ""; skip = 1; next }
    /^<!-- demo:end -->$/ { skip = 0 }
    !skip { print }
  ' "$readme"
)"

if ((write)); then
  printf '%s\n' "$expected" >"$readme"
elif ! diff -u --label README.md --label "README.md (actual output)" "$readme" <(printf '%s\n' "$expected"); then
  echo "The README's example is out of date; run 'just readme-demo --write'." >&2
  exit 1
fi
