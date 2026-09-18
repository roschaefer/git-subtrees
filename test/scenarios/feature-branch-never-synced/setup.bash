# See README.md in this directory.
scenario_feature_branch_never_synced() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  (
    cd "$monorepo"
    git remote add vendor/a "$upstream"
    git fetch -q vendor/a
    git checkout -q -b feature
    mkdir -p vendor/a
    echo "pre-existing" >vendor/a/other.txt
    git add vendor/a
    git commit -q -m "pre-existing"
  )
}
