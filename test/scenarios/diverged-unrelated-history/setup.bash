# See README.md in this directory.
scenario_diverged_unrelated_history() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  connect_subtree "$monorepo" "$upstream" "vendor/a"
  (
    cd "$monorepo"
    echo "local change" >>vendor/a/file.txt
    git add vendor/a/file.txt
    git commit -q -m "local change"
  )

  # Blow away upstream and replace it with a completely unrelated history.
  rm -rf "$upstream"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "brand new unrelated history"

  (cd "$monorepo" && git fetch -q vendor/a)
}
