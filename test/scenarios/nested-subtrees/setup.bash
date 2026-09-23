# See README.md in this directory.
scenario_nested_subtrees() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/pkg"
  (
    cd "$monorepo"
    # Written to the config directly: `git remote add` refuses this name
    # since Git 2.51, but older versions accept it.
    git config remote.vendor/pkg/extra.url "$upstream"
    git config remote.vendor/pkg/extra.fetch "+refs/heads/*:refs/remotes/vendor/pkg/extra/*"
    mkdir -p vendor/pkg/extra
    echo "inner" >vendor/pkg/extra/file.txt
    git add vendor/pkg/extra
    git commit -q -m "add vendor/pkg/extra"
  )
}
