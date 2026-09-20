# Assumes lib/common.sh is already sourced.

usage_diff() {
  cat <<'EOF'
usage: git subtrees diff [--base <branch>] [path...]

Shows the committed file changes that 'git subtrees push' would send to
each subtree remote. Purely local -- run 'git subtrees fetch' first for
up-to-date results. Defaults to every discovered subtree when no paths
are given.

For a subtree whose remote has no branch named like the current one, the
diff is against the monorepo's base branch (--base, else origin/HEAD,
else init.defaultBranch). On the base branch itself, the whole subtree is
shown as new remote content.
EOF
}

# Shows the remote-to-local patch for one subtree. $3 is an explicit
# --base branch, if any.
diff_one() {
  local path="$1" branch="$2" base="${3:-}"
  local local_tree old_tree empty_tree

  classify_subtree "$path" "$branch"

  case "$SUBTREE_STATE" in
    not-connected)
      log_warn "$path: not fetched -- run 'git subtrees fetch $path' first"
      return 1
      ;;
    up-to-date | pull)
      return 0
      ;;
    unrelated-history)
      log_warn "$path: remote and local share no history -- no push diff available"
      return 1
      ;;
    missing-at-head)
      changes_vs_base "$path" "$base"
      case "$SUBTREE_CHANGES_VS_BASE" in
        no)
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
          log_err "$path: could not compare with base branch '$SUBTREE_BASE_BRANCH'"
          return 1
          ;;
        yes)
          old_tree="$(git rev-parse "$SUBTREE_BASE_MERGE_BASE:$path" 2>/dev/null || true)"
          ;;
        self)
          old_tree=""
          ;;
      esac
      ;;
    push | diverged)
      old_tree="$SUBTREE_TARGET_REF"
      ;;
  esac

  local_tree="$(git rev-parse "HEAD:$path" 2>/dev/null || true)"
  [[ -n "$local_tree" ]] || {
    log_err "$path: cannot resolve subtree content at HEAD"
    return 1
  }

  if [[ -z "$old_tree" ]]; then
    empty_tree="$(git hash-object -t tree /dev/null)"
    old_tree="$empty_tree"
  fi

  log_step "$path"
  git --no-pager diff "$old_tree" "$local_tree"
}

cmd_diff() {
  parse_base_args usage_diff "$@"
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
    die "no subtrees discovered -- nothing to diff"
  fi

  local path
  for path in "${paths[@]}"; do
    is_subtree_path "$path" || die "not a subtree path: $path"
  done

  local failures=()
  for path in "${paths[@]}"; do
    diff_one "$path" "$branch" "$base" || failures+=("$path")
  done

  if [[ ${#failures[@]} -gt 0 ]]; then
    log_err "Failed: ${failures[*]}"
    return 1
  fi
}
