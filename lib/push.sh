# Assumes lib/common.sh is already sourced.

usage_push() {
  cat <<'EOF'
usage: git subtrees push [path...]

Pushes local subtree changes upstream. Defaults to every discovered
subtree with changes when no paths are given. Shares one SSH connection
(ControlMaster/ControlPersist) across pushes to the same host.

On an unrelated-history divergence (no shared ancestor at all), push does
not attempt to push -- it prints manual recovery commands instead.
EOF
}

# Pushes a single subtree path. Factored out from cmd_push's loop so bats
# can exercise one path directly.
push_one() {
  local path="$1" branch="$2"

  if ! usable_with_git_subtree "$path"; then
    log_err "$path: git-subtree cannot use a name starting with '-' -- rename it and re-run"
    return 1
  fi
  if ! usable_with_git_subtree "$branch"; then
    log_err "$branch: git-subtree cannot use a branch name starting with '-' -- rename it and re-run"
    return 1
  fi

  classify_subtree "$path" "$branch"

  case "$SUBTREE_STATE" in
    not-connected)
      log_warn "$path: not fetched -- run 'git subtrees fetch $path' first"
      return 1
      ;;
    up-to-date | pull)
      log_ok "$path: nothing to push"
      return 0
      ;;
    unrelated-history)
      print_unrelated_history_guidance "$path" "$branch"
      return 1
      ;;
    missing-at-head)
      log_warn "$path: remote has no '$branch' branch yet -- this push will create it"
      ;;
    push | diverged) ;;
  esac

  if ! git subtree push --prefix="$path" "$path" "$branch"; then
    log_err "$path: push failed"
    return 1
  fi
  log_ok "$path: pushed"
}

cmd_push() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage_push
    exit 0
  fi
  [[ "${1:-}" == "--" ]] && shift

  cd_to_repo_root
  discover_subtrees
  local branch
  branch="$(current_branch)"

  local paths=("$@")
  if [[ ${#paths[@]} -eq 0 ]]; then
    paths=("${ALL_PATHS[@]}")
  fi
  if [[ ${#paths[@]} -eq 0 ]]; then
    die "no subtrees discovered -- nothing to push"
  fi

  local path
  for path in "${paths[@]}"; do
    is_subtree_path "$path" || die "not a subtree path: $path"
  done

  local ssh_control_dir
  ssh_control_dir="$(mktemp -d)"
  export GIT_SSH_COMMAND="ssh -o ControlMaster=auto -o ControlPersist=60s -o ControlPath=$ssh_control_dir/%r@%h:%p"

  local failures=()
  for path in "${paths[@]}"; do
    push_one "$path" "$branch" || failures+=("$path")
  done

  rm -rf "$ssh_control_dir"

  if [[ ${#failures[@]} -gt 0 ]]; then
    log_err "Failed: ${failures[*]}"
    exit 1
  fi
}
