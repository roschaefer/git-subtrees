# Assumes lib/common.sh, lib/fetch.sh and lib/merge.sh are already sourced.

usage_pull() {
  cat <<'EOF'
usage: git subtrees pull [path...]

Fetches every subtree's remote in parallel, then squash-merges upstream
changes into each subtree path -- 'git subtrees fetch' followed by
'git subtrees merge'. Defaults to every discovered subtree when
no paths are given. Always uses --squash: never a plain merge, so the
remote's raw history never becomes a literal parent of HEAD.

On an ordinary conflict (both sides changed but share history), resolve it
and run plain 'git commit', then re-run pull. On an unrelated-history
divergence (no shared ancestor at all), pull does not attempt an automatic
merge -- it prints manual recovery commands instead.
EOF
}

# Pulls a single subtree path: fetch (unless skip_fetch is set, e.g. because
# cmd_pull already fetched every path in parallel), then merge -- plain
# `git pull` is `git fetch` + `git merge`. Factored out from cmd_pull's loop
# so bats can exercise one path directly.
pull_one() {
  local path="$1" branch="$2" skip_fetch="${3:-}"

  # Validate before fetching so a bad name never costs a network round-trip.
  require_usable_names "$path" "$branch" || return 1

  if [[ -z "$skip_fetch" ]]; then
    fetch_one "$path" "$branch" || return 1
  fi

  merge_one "$path" "$branch" pull
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
