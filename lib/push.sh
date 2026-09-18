# Assumes lib/common.sh is already sourced.

usage_push() {
  cat <<'EOF'
usage: git subtrees push [--base <branch>] [path...]

Pushes local subtree changes upstream. Defaults to every discovered
subtree with changes when no paths are given. Shares one SSH connection
(ControlMaster/ControlPersist) across pushes to the same host.

If the remote has no branch named like the current one, push creates it --
but only for a subtree that changed on this branch compared with the
monorepo's base branch (the branch this one was cut from), so working on a
feature branch doesn't spawn empty branches on every remote. The base
branch is taken from --base, else from origin/HEAD, else from
init.defaultBranch; if none of those resolves, push refuses and asks for
--base. On the base branch itself there is nothing to compare, and push
creates the missing branch.

On an unrelated-history divergence (no shared ancestor at all), push does
not attempt to push -- it prints manual recovery commands instead.
EOF
}

# Pushes a single subtree path. Factored out from cmd_push's loop so bats
# can exercise one path directly. $3 is an explicit --base branch, if any.
push_one() {
  local path="$1" branch="$2" base="${3:-}"

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
      changes_vs_base "$path" "$base"
      case "$SUBTREE_CHANGES_VS_BASE" in
        no)
          log_ok "$path: nothing to push (remote has no '$branch' branch; unchanged since '$SUBTREE_BASE_BRANCH')"
          return 0
          ;;
        unresolved)
          if [[ -n "$base" ]]; then
            log_err "$path: base branch '$base' not found, or it shares no history with '$branch'"
          else
            log_err "$path: remote has no '$branch' branch and the monorepo's base branch can't be determined -- re-run with --base <branch>"
          fi
          return 1
          ;;
        error)
          log_err "$path: could not compare with base branch '$SUBTREE_BASE_BRANCH' -- not creating '$branch'"
          return 1
          ;;
        yes)
          log_warn "$path: remote has no '$branch' branch yet -- this push will create it (changed since '$SUBTREE_BASE_BRANCH')"
          ;;
        self)
          log_warn "$path: remote has no '$branch' branch yet -- this push will create it"
          ;;
      esac
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
  parse_base_args usage_push "$@"
  local base="$BASE_ARG"
  local paths=("${PATH_ARGS[@]}")

  cd_to_repo_root
  discover_subtrees
  local branch
  branch="$(current_branch)"

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
    push_one "$path" "$branch" "$base" || failures+=("$path")
  done

  rm -rf "$ssh_control_dir"

  if [[ ${#failures[@]} -gt 0 ]]; then
    log_err "Failed: ${failures[*]}"
    exit 1
  fi
}
