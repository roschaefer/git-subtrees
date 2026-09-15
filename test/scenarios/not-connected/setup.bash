# See README.md in this directory.
scenario_not_connected() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  (
    cd "$monorepo"
    mkdir -p vendor/a
    git remote add vendor/a "$upstream"
  )
  # Deliberately never fetched.
}
