# See README.md in this directory.
scenario_diverged_then_pulled() {
  local monorepo="$1" upstream="$2" tmp
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/a"
  (
    cd "$monorepo"
    echo "local change" >vendor/a/local.txt
    git add vendor/a/local.txt
    git commit -q -m "local change"
  )
  tmp="$(mktemp -d)"
  git clone -q "$upstream" "$tmp" 2>/dev/null
  (
    cd "$tmp"
    git config user.name "Test"
    git config user.email "test@example.com"
    echo "upstream change" >upstream.txt
    git add upstream.txt
    git commit -q -m "upstream change"
    git push -q origin HEAD:main
  )
  rm -rf "$tmp"
  (
    cd "$monorepo"
    git fetch -q vendor/a
    git subtree pull -q --prefix=vendor/a vendor/a main --squash -m "pull vendor/a" >/dev/null 2>&1
  )
}
