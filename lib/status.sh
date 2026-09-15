# Assumes lib/common.sh is already sourced.

usage_status() {
  cat <<'EOF'
usage: git subtrees status [path...]

Shows the sync state of every subtree, plus every registered remote that
has no matching directory ("no mapping"). Purely local -- run 'git subtrees
fetch' first for up-to-date results. Defaults to every discovered subtree
when no paths are given.
EOF
}

# Classifies and prints the status of one subtree path.
format_status_line() {
  local path="$1" branch="$2"
  classify_subtree "$path" "$branch"

  case "$SUBTREE_STATE" in
    not-connected)
      log_warn "$path -> $SUBTREE_URL (never fetched -- run 'git subtrees fetch $path')"
      ;;
    missing-at-head)
      log_warn "$path -> $SUBTREE_URL (remote has no '$branch' branch)"
      ;;
    up-to-date)
      log_ok "$path -> $SUBTREE_URL (up to date)"
      ;;
    push | pull | diverged)
      log_ok "$path -> $SUBTREE_URL ($SUBTREE_STATE)"
      local local_tree
      local_tree="$(git rev-parse "HEAD:$path" 2>/dev/null || true)"
      # Diff order follows what the pending operation would apply, so
      # insertions in the diffstat always mean "content gained": push
      # diffs remote->local (what push would add to remote), pull diffs
      # local->remote (what pull would add to local). diverged has no
      # single right direction; remote->local is picked for consistency.
      case "$SUBTREE_STATE" in
        pull) git diff --stat "$local_tree" "$SUBTREE_TARGET_REF" 2>/dev/null || true ;;
        *) git diff --stat "$SUBTREE_TARGET_REF" "$local_tree" 2>/dev/null || true ;;
      esac
      ;;
    unrelated-history)
      log_warn "$path -> $SUBTREE_URL (unrelated history -- see 'git subtrees pull $path' for options)"
      ;;
  esac
}

cmd_status() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage_status
    exit 0
  fi

  discover_subtrees
  local branch
  branch="$(current_branch)"

  local paths=("$@")
  if [[ ${#paths[@]} -eq 0 ]]; then
    paths=("${ALL_PATHS[@]}")
  fi

  local path
  for path in "${paths[@]}"; do
    is_subtree_path "$path" || die "not a subtree path: $path"
  done

  local remote
  for remote in "${ALL_REMOTES[@]}"; do
    is_subtree_path "$remote" || log_warn "$remote -> (no mapping)"
  done

  for path in "${paths[@]}"; do
    format_status_line "$path" "$branch"
  done
}
