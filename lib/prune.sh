# Assumes lib/common.sh is already sourced.

usage_prune() {
  cat <<'EOF'
usage: git subtrees prune [-n|--dry-run] [path...]

Prunes stale refs for subtree remotes, like 'git remote prune <remote>'.
Defaults to every discovered subtree when no paths are given. This follows
the remote's configured fetch refspecs; use --dry-run first if the remote
has non-branch refspecs such as explicit tag mappings.
EOF
}

cmd_prune() {
  local dry_run=false
  local paths=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        usage_prune
        exit 0
        ;;
      -n | --dry-run)
        dry_run=true
        ;;
      --)
        shift
        paths+=("$@")
        break
        ;;
      *)
        paths+=("$1")
        ;;
    esac
    shift
  done

  cd_to_repo_root
  discover_subtrees

  if [[ ${#paths[@]} -eq 0 ]]; then
    paths=("${ALL_PATHS[@]}")
  fi
  if [[ ${#paths[@]} -eq 0 ]]; then
    die "no subtrees discovered -- nothing to prune"
  fi

  local path failures=()
  for path in "${paths[@]}"; do
    is_subtree_path "$path" || die "not a subtree path: $path"
  done

  for path in "${paths[@]}"; do
    if "$dry_run"; then
      git remote prune --dry-run -- "$path" || failures+=("$path")
    else
      git remote prune -- "$path" || failures+=("$path")
    fi
  done

  if [[ ${#failures[@]} -gt 0 ]]; then
    log_err "Failed: ${failures[*]}"
    exit 1
  fi
}
