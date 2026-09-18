# See README.md in this directory.
scenario_feature_branch_changed() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/a"
  (
    cd "$monorepo"
    git checkout -q -b feature
    echo "local change" >>vendor/a/file.txt
    git add vendor/a/file.txt
    git commit -q -m "local change"
  )
}
