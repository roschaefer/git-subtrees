# See README.md in this directory.
scenario_init_on_feature_branch() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  (
    cd "$monorepo"
    git config init.defaultBranch main
    git checkout -q -b feature
  )
}
