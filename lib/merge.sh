# Assumes lib/common.sh is already sourced.

usage_merge() {
  cat <<'EOF'
usage: git subtrees merge [path...]

Squash-merges the already-fetched upstream changes into each subtree path,
without contacting any remote (run 'git subtrees fetch' first, or use
'git subtrees pull' to do both). Defaults to every discovered subtree when
no paths are given. Always uses --squash: never a plain merge, so the
remote's raw history never becomes a literal parent of HEAD.

On an ordinary conflict (both sides changed but share history), resolve it
and run plain 'git commit', then re-run merge. On an unrelated-history
divergence (no shared ancestor at all), merge does not attempt an automatic
merge -- it prints manual recovery commands instead.
EOF
}

# Rejects names `git subtree` would parse as options.
require_usable_names() {
  local path="$1" branch="$2"
  if ! usable_with_git_subtree "$path"; then
    log_err "$path: git-subtree cannot use a name starting with '-' -- rename it and re-run"
    return 1
  fi
  if ! usable_with_git_subtree "$branch"; then
    log_err "$branch: git-subtree cannot use a branch name starting with '-' -- rename it and re-run"
    return 1
  fi
}

# Merges a single subtree path from its already-fetched tracking ref;
# never touches the network. `verb` (merge|pull) only selects the wording
# of the messages, so pull keeps reporting "pulled" while sharing this code.
merge_one() {
  local path="$1" branch="$2" verb="${3:-merge}"

  require_usable_names "$path" "$branch" || return 1

  classify_subtree "$path" "$branch"

  case "$SUBTREE_STATE" in
    not-connected)
      if [[ "$verb" == pull ]]; then
        log_warn "$path: still not fetched after fetch -- does the remote exist?"
      else
        log_warn "$path: not fetched yet -- run 'git subtrees fetch' first"
      fi
      return 1
      ;;
    missing-at-head)
      log_ok "$path: remote has no '$branch' branch -- nothing to $verb"
      return 0
      ;;
    up-to-date | push)
      log_ok "$path: nothing to $verb"
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
    log_err "$path: $verb failed -- resolve any conflicts, 'git commit', then re-run $verb"
    return 1
  fi
  log_ok "$path: $([[ "$verb" == pull ]] && echo pulled || echo merged)"
}

cmd_merge() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage_merge
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
    die "no subtrees discovered -- nothing to merge"
  fi

  local path
  for path in "${paths[@]}"; do
    is_subtree_path "$path" || die "not a subtree path: $path"
  done

  local failures=()
  local -A seen=()
  for path in "${paths[@]}"; do
    [[ -n "${seen[$path]:-}" ]] && continue
    seen[$path]=1
    merge_one "$path" "$branch" || failures+=("$path")
  done

  if [[ ${#failures[@]} -gt 0 ]]; then
    log_err "Failed: ${failures[*]}"
    exit 1
  fi
}
