# Assumes lib/common.sh (and, via fetch_one, lib/fetch.sh) is already sourced.

usage_pull() {
  cat <<'EOF'
usage: git subtrees pull [path...]

Fetches then squash-merges upstream changes into each subtree path.
Defaults to every discovered subtree when no paths are given. Always uses
--squash: never a plain merge, so the remote's raw history never becomes a
literal parent of HEAD.

On an ordinary conflict (both sides changed but share history), resolve it
and run plain 'git commit', then re-run pull. On an unrelated-history
divergence (no shared ancestor at all), pull does not attempt an automatic
merge -- it prints manual recovery commands instead.
EOF
}

# Pulls a single subtree path. Fetches first, then classifies and acts.
# Factored out from cmd_pull's loop so bats can exercise one path directly.
pull_one() {
  local path="$1" branch="$2"
  fetch_one "$path" || return 1

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

  if ! git subtree pull --prefix="$path" "$path" "$branch" --squash; then
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

  local failures=()
  for path in "${paths[@]}"; do
    pull_one "$path" "$branch" || failures+=("$path")
  done

  if [[ ${#failures[@]} -gt 0 ]]; then
    log_err "Failed: ${failures[*]}"
    exit 1
  fi
}
