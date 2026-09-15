# See README.md in this directory.
scenario_diverged_common_ancestor() {
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
  seed_bare_repo "$upstream" "upstream change"
  (cd "$monorepo" && git fetch -q vendor/a)
}
