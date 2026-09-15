# Assumes lib/common.sh is already sourced.

usage_fetch() {
  cat <<'EOF'
usage: git subtrees fetch [path...]

Fetches every subtree's remote, updating refs/remotes/<name>/* only --
never FETCH_HEAD. Defaults to every discovered subtree when no paths are
given. Runs fetches in parallel.
EOF
}

# Single synchronous fetch of one subtree's remote. Factored out so it can
# be invoked directly (e.g. from tests) without the parallel/wait plumbing
# in cmd_fetch.
fetch_one() {
  local remote="$1"
  if git fetch --quiet --no-write-fetch-head "$remote"; then
    log_ok "$remote fetched"
  else
    log_err "$remote fetch failed"
    return 1
  fi
}

cmd_fetch() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage_fetch
    exit 0
  fi

  discover_subtrees

  local paths=("$@")
  if [[ ${#paths[@]} -eq 0 ]]; then
    paths=("${ALL_PATHS[@]}")
  fi
  if [[ ${#paths[@]} -eq 0 ]]; then
    die "no subtrees discovered -- nothing to fetch"
  fi

  local path
  for path in "${paths[@]}"; do
    is_subtree_path "$path" || die "not a subtree path: $path"
  done

  local tmp_dir
  tmp_dir="$(mktemp -d)"

  local pids=() i=0
  for path in "${paths[@]}"; do
    fetch_one "$path" >"$tmp_dir/$i.out" 2>&1 &
    pids+=("$!")
    i=$((i + 1))
  done

  local failures=() idx=0 pid
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      failures+=("${paths[$idx]}")
    fi
    cat "$tmp_dir/$idx.out"
    idx=$((idx + 1))
  done
  rm -rf "$tmp_dir"

  if [[ ${#failures[@]} -gt 0 ]]; then
    log_err "Failed: ${failures[*]}"
    exit 1
  fi
}
