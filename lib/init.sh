# Assumes lib/common.sh (and, via fetch_one, lib/fetch.sh) is already sourced.

usage_init() {
  cat <<'EOF'
usage: git subtrees init <path> <url>

One-time bootstrap connecting worktree directory <path> to <url> as a
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

  local path="${1:-}" url="${2:-}"
  if [[ -z "$path" || -z "$url" ]]; then
    usage_init >&2
    exit 1
  fi

  local existing_url
  existing_url="$(git remote get-url "$path" 2>/dev/null || true)"

  if [[ -n "$existing_url" && "$existing_url" != "$url" ]]; then
    die "$path: remote already registered, pointing at '$existing_url' (not '$url')"
  fi

  if [[ -z "$existing_url" ]]; then
    log_step "$path: registering remote -> $url"
    git remote add "$path" "$url"
  fi

  log_step "$path: fetching"
  fetch_one "$path" || die "$path: fetch failed"

  local branch
  branch="$(current_branch)"

  classify_subtree "$path" "$branch"

  if [[ "$SUBTREE_STATE" == "missing-at-head" ]]; then
    log_ok "$path: remote has no '$branch' branch yet -- nothing to connect"
    return 0
  fi

  if [[ ! -d "$path" ]]; then
    log_step "$path: adding subtree from $url"
    git subtree add --prefix="$path" "$path" "$branch" --squash
    log_ok "$path: connected"
    return 0
  fi

  case "$SUBTREE_STATE" in
    up-to-date | push | pull | diverged)
      log_ok "$path: already connected"
      ;;
    unrelated-history)
      log_err "$path: directory exists with content unrelated to $url"
      log_err "move it aside and re-run: mv $path $path.bak && git subtrees init $path $url"
      exit 1
      ;;
    *)
      die "$path: remote has no branches to connect to"
      ;;
  esac
}
