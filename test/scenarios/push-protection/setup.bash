# See README.md in this directory.
scenario_push_protection() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/a"
  (
    cd "$monorepo"
    # As if added with a plain `git remote add`, not `git subtrees init`.
    git config --unset remote.vendor/a.pushurl
    mkdir internal
    echo "not for the public" >internal/notes.txt
    git add internal
    git commit -q -m "add internal notes"
  )
}
