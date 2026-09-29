# shellcheck shell=bash
# Sourced by the hidden first scrut block of README.md, so the example
# session there runs against this checkout; see `just readme-demo`.
#
# Builds a monorepo with three subtrees in the scrut work directory -- ui
# changed upstream, api changed locally, lib in sync -- and cds into it.
# Author, committer and dates are fixed, so commit hashes are the same on
# every run.

demo="$PWD"
PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd):$PATH"
export GIT_CONFIG_GLOBAL="$demo/gitconfig" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=demo GIT_AUTHOR_EMAIL=demo@example.com
export GIT_COMMITTER_NAME=demo GIT_COMMITTER_EMAIL=demo@example.com
export GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z

build_scenario() {
  local repo
  git config --global init.defaultBranch main

  for repo in api lib ui; do
    git init -q --bare "$demo/up/$repo.git"
    git clone -q "$demo/up/$repo.git" "$demo/seed-$repo" 2>/dev/null
    echo "$repo v1" >"$demo/seed-$repo/README.md"
    git -C "$demo/seed-$repo" add README.md
    git -C "$demo/seed-$repo" commit -q -m "$repo: first"
    git -C "$demo/seed-$repo" push -q origin main
  done

  git init -q "$demo/mono"
  cd "$demo/mono" || return
  git commit -q --allow-empty -m initial
  git subtrees init packages/api "$demo/up/api.git" >/dev/null 2>&1
  git subtrees init packages/ui "$demo/up/ui.git" >/dev/null 2>&1
  git subtrees init vendor/lib "$demo/up/lib.git" >/dev/null 2>&1

  echo "ui v2" >>"$demo/seed-ui/README.md"
  git -C "$demo/seed-ui" commit -q -am "ui: new button"
  git -C "$demo/seed-ui" push -q origin main

  echo "api v2" >>packages/api/README.md
  git add packages/api
  git commit -q -m "api: add endpoint"
}

build_scenario
unset -f build_scenario

# The README shows what a terminal shows, stderr included, with the
# scratch remotes as https://example.com/<name>.git. git subtree split's
# progress counter rewrites itself with \r; only what follows the last \r
# of a line stays.
git() {
  command git "$@" 2>&1 |
    sed -E "s#\r\$##; s#.*\r##; s#$demo/up/([a-z]+)\.git#https://example.com/\1.git#g"
  return "${PIPESTATUS[0]}"
}
