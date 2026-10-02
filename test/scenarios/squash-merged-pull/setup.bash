# See README.md in this directory.
scenario_squash_merged_pull() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/a"
  seed_bare_repo "$upstream" "upstream change"
  (
    cd "$monorepo"
    git switch -q -c feature
    git fetch -q vendor/a
    git subtree pull -q --prefix=vendor/a vendor/a main --squash -m "pull vendor/a" >/dev/null 2>&1
    git switch -q main
    git merge -q --squash feature >/dev/null
    git commit -q -m "feature (squash-merged)"
    git branch -q -D feature
    echo "local change" >vendor/a/local.txt
    git add vendor/a/local.txt
    git commit -q -m "local change"
  )
}
