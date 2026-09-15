# See README.md in this directory.
scenario_push_ahead() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/a"
  (
    cd "$monorepo"
    echo "local change" >>vendor/a/file.txt
    git add vendor/a/file.txt
    git commit -q -m "local change"
  )
}
