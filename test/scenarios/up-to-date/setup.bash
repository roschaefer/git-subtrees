# See README.md in this directory.
scenario_up_to_date() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  connect_subtree "$monorepo" "$upstream" "vendor/a"
}
