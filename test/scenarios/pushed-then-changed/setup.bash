# See README.md in this directory.
scenario_pushed_then_changed() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/a"
  (
    cd "$monorepo"
    echo "pushed change" >>vendor/a/file.txt
    git add vendor/a/file.txt
    git commit -q -m "pushed change"
    push_one vendor/a main >/dev/null 2>&1
    git fetch -q vendor/a
    echo "later change" >>vendor/a/file.txt
    git add vendor/a/file.txt
    git commit -q -m "later change"
  )
}
