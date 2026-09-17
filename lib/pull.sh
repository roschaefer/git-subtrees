# Assumes lib/common.sh (and, via fetch_one, lib/fetch.sh) is already sourced.

usage_pull() {
  cat <<'EOF'
usage: git subtrees pull [path...]

Fetches every subtree's remote in parallel, then squash-merges upstream
changes into each subtree path. Defaults to every discovered subtree when
no paths are given. Always uses --squash: never a plain merge, so the
remote's raw history never becomes a literal parent of HEAD.

On an ordinary conflict (both sides changed but share history), resolve it
and run plain 'git commit', then re-run pull. On an unrelated-history
divergence (no shared ancestor at all), pull does not attempt an automatic
merge -- it prints manual recovery commands instead.
EOF
}

# Pulls a single subtree path. Fetches first (unless skip_fetch is set,
# e.g. because cmd_pull already fetched every path in parallel), then
# classifies and acts. Factored out from cmd_pull's loop so bats can
# exercise one path directly.
pull_one() {
  local path="$1" branch="$2" skip_fetch="${3:-}"

  if ! usable_with_git_subtree "$path"; then
    log_err "$path: git-subtree cannot use a name starting with '-' -- rename it and re-run"
    return 1
  fi
  if ! usable_with_git_subtree "$branch"; then
    log_err "$branch: git-subtree cannot use a branch name starting with '-' -- rename it and re-run"
    return 1
  fi

  if [[ -z "$skip_fetch" ]]; then
    fetch_one "$path" "$branch" || return 1
  fi

  classify_subtree "$path" "$branch"

  case "$SUBTREE_STATE" in
    not-connected)
      log_warn "$path: still not fetched after fetch -- does the remote exist?"
      return 1
      ;;
    missing-at-head)
      log_ok "$path: remote has no '$branch' branch -- nothing to pull"
      return 0
      ;;
    up-to-date | push)
      log_ok "$path: nothing to pull"
      return 0
      ;;
    unrelated-history)
      print_unrelated_history_guidance "$path" "$branch"
      return 1
      ;;
    pull | diverged) ;;
  esac

  # `git subtree pull` would fetch $path/$branch itself before merging,
  # redoing the network round-trip fetch_one (or cmd_pull's parallel
  # fetch phase) just paid for. `git subtree merge` performs the same
  # squash-merge without fetching, given the tracking ref classify_subtree
  # already resolved.
  #
  # git-subtree's own REPOSITORY fallback (fetching a missing
  # git-subtree-split object on demand) isn't safe to reach for here: it's
  # only an optional 2nd positional arg to `merge` on newer git, but on
  # e.g. git 2.31 `merge` hard-validates that every arg past --prefix
  # resolves as a revision, and dies with "Use --prefix instead of bare
  # filenames" the moment you pass a bare path/remote name as that 2nd
  # arg. So replicate the fallback ourselves instead, using the split SHA
  # classify_subtree already resolved.
  if [[ -n "$SUBTREE_SPLIT_SHA" ]] && ! git cat-file -e "${SUBTREE_SPLIT_SHA}^{commit}" 2>/dev/null; then
    if git fetch --quiet -- "$path" "$SUBTREE_SPLIT_SHA" 2>/dev/null &&
      ! git merge-base "$SUBTREE_SPLIT_SHA" "$SUBTREE_TARGET_REF" >/dev/null 2>&1; then
      print_unrelated_history_guidance "$path" "$branch"
      return 1
    fi
  fi

  if ! git subtree merge --prefix="$path" --squash "$SUBTREE_TARGET_REF"; then
    log_err "$path: pull failed -- resolve any conflicts, 'git commit', then re-run pull"
    return 1
  fi
  log_ok "$path: pulled"
}

cmd_pull() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage_pull
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
    die "no subtrees discovered -- nothing to pull"
  fi

  local path
  for path in "${paths[@]}"; do
    is_subtree_path "$path" || die "not a subtree path: $path"
  done

  fetch_all_parallel_for_branch "$branch" "${paths[@]}"
  local failures=("${FETCH_FAILURES[@]}")

  local i path
  for i in "${!FETCH_PATHS[@]}"; do
    path="${FETCH_PATHS[$i]}"
    print_fetch_output "$i"

    fetch_failed_for_path "$path" && continue

    pull_one "$path" "$branch" skip-fetch || failures+=("$path")
  done

  if [[ ${#failures[@]} -gt 0 ]]; then
    log_err "Failed: ${failures[*]}"
    exit 1
  fi
}
