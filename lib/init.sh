# Assumes lib/common.sh (and, via fetch_one, lib/fetch.sh) is already sourced.

usage_init() {
  cat <<'EOF'
usage: git subtrees init <path> <url>

One-time bootstrap adding/adopting worktree directory <path> from <url> as a
subtree, registering a remote named <path> if one doesn't already exist.
Requires exactly one <path> <url> pair -- unlike every other command, init
is not batchable across all discovered subtrees, since it's the one
operation that needs human judgment.
EOF
}

cmd_init() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage_init
    exit 0
  fi
  [[ "${1:-}" == "--" ]] && shift

  local path="${1:-}" url="${2:-}"
  if [[ -z "$path" || -z "$url" ]]; then
    usage_init >&2
    exit 1
  fi
  usable_with_git_subtree "$path" || die "$path: git-subtree cannot use a name starting with '-' -- rename it and re-run"

  cd_to_repo_root

  local branch
  branch="$(current_branch)"
  usable_with_git_subtree "$branch" || die "$branch: git-subtree cannot use a branch name starting with '-' -- rename it and re-run"

  discover_subtrees
  local nested
  if nested="$(overlapping_remote "$path")"; then
    die "nested subtrees are not supported: $(overlap_pair "$path" "$nested") overlap"
  fi

  local existing_url
  existing_url="$(git remote get-url -- "$path" 2>/dev/null || true)"

  if [[ -n "$existing_url" && "$existing_url" != "$url" ]]; then
    die "$path: remote already registered, pointing at '$existing_url' (not '$url')"
  fi

  if [[ -z "$existing_url" ]]; then
    log_step "$path: registering remote -> $url"
    git remote add -- "$path" "$url"
  fi

  log_step "$path: fetching"
  # Deferred: `git fetch` and fetch_one's own log_err already write a fatal
  # diagnostic to stderr the moment the branch fetch fails, before we get a
  # chance to check whether that's actually the documented no-op below.
  # Capture it instead of letting it print immediately, and only replay it
  # once remote_missing_branch has ruled out the missing-branch case --
  # otherwise a successful (exit 0) no-op still leaves a misleading "fetch
  # failed" on stderr.
  local fetch_err fetch_status=0
  {
    fetch_err="$(fetch_one "$path" "$branch" 2>&1 1>&3)" || fetch_status=$?
  } 3>&1
  if ((fetch_status != 0)); then
    if remote_missing_branch "$path" "$branch"; then
      log_ok "$path: remote has no '$branch' branch yet -- nothing to add"
      return 0
    fi
    printf '%s\n' "$fetch_err" >&2
    die "$path: fetch failed"
  fi

  classify_subtree "$path" "$branch"

  if [[ "$SUBTREE_STATE" == "missing-at-head" ]]; then
    log_ok "$path: remote has no '$branch' branch yet -- nothing to add"
    return 0
  fi

  if [[ ! -d "$path" ]]; then
    log_step "$path: adding subtree from $url"
    git subtree add --prefix="$path" "$path" "$branch" --squash
    log_ok "$path: added"
    return 0
  fi

  case "$SUBTREE_STATE" in
    up-to-date | push | pull | diverged)
      log_ok "$path: already initialized"
      ;;
    unrelated-history)
      log_err "$path: directory exists with content unrelated to $url"
      log_err "move it aside and re-run: mv $path $path.bak && git subtrees init $path $url"
      exit 1
      ;;
    *)
      die "$path: remote has no branches to add"
      ;;
  esac
}
