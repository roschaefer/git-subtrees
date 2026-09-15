# See README.md in this directory.
scenario_init_unrelated_content() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  (
    cd "$monorepo"
    mkdir -p vendor/a
    echo "pre-existing, unrelated content" >vendor/a/other.txt
    git add vendor/a
    git commit -q -m "pre-existing content"
  )
  # Deliberately: no remote registered yet -- cmd_init registers it itself.
}
