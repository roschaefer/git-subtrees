# Assumes lib/common.sh (and, via fetch_one, lib/fetch.sh) is already sourced.

usage_init() {
  cat <<'EOF'
usage: git subtrees init [--base <branch>] <path> <url>

One-time bootstrap adding/adopting worktree directory <path> from <url> as a
subtree, registering a remote named <path> if one doesn't already exist.
Requires exactly one <path> <url> pair -- unlike every other command, init
is not batchable across all discovered subtrees, since it's the one
operation that needs human judgment.

If the remote has no branch named like the current one (e.g. on a fresh
feature branch), init adds the remote's branch named like the monorepo's
base branch instead, so your first push creates the missing branch on top
of it. The base branch is taken from --base, else from origin/HEAD, else
from init.defaultBranch. If none resolves, or the remote lacks that branch
too (e.g. it's empty), init only registers the remote.
EOF
}

# Fetches <branch> of remote <path> for init. Returns 0 on success and 2 if
# the remote has no such branch; dies on any other fetch failure.
init_fetch() {
  local path="$1" branch="$2"
  # Deferred: `git fetch` and fetch_one's own log_err already write a fatal
  # diagnostic to stderr the moment the branch fetch fails, before we get a
  # chance to check whether that's actually the missing-branch case.
  # Capture it instead of letting it print immediately, and only replay it
  # once remote_missing_branch has ruled that out -- otherwise a successful
  # (exit 0) no-op still leaves a misleading "fetch failed" on stderr.
  local fetch_err fetch_status=0
  {
    fetch_err="$(fetch_one "$path" "$branch" 2>&1 1>&3)" || fetch_status=$?
  } 3>&1
  ((fetch_status == 0)) && return 0
  remote_missing_branch "$path" "$branch" && return 2
  printf '%s\n' "$fetch_err" >&2
  die "$path: fetch failed"
}

# Prints the name the monorepo's base branch has on a subtree remote:
# "main" for refs/heads/main as well as for origin/main. Fails if no base
# branch resolves (see resolve_base_ref).
base_branch_name() {
  local ref name
  ref="$(resolve_base_ref "$1")" || return 1
  name="${ref#refs/heads/}"
  name="${name#refs/remotes/}"
  printf '%s\n' "${name#origin/}"
}

cmd_init() {
  parse_base_args usage_init "$@"
  local base="$BASE_ARG"
  local path="${PATH_ARGS[0]:-}" url="${PATH_ARGS[1]:-}"
  if [[ -z "$path" || -z "$url" || ${#PATH_ARGS[@]} -gt 2 ]]; then
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
  local rc=0
  init_fetch "$path" "$branch" || rc=$?
  if ((rc == 2)); then
    local base_branch
    if ! base_branch="$(base_branch_name "$base")"; then
      log_ok "$path: remote has no '$branch' branch yet -- nothing to add (pass --base <branch> to add another branch)"
      return 0
    fi
    if [[ "$base_branch" != "$branch" ]] && usable_with_git_subtree "$base_branch"; then
      rc=0
      init_fetch "$path" "$base_branch" || rc=$?
    fi
    if ((rc != 0)); then
      log_ok "$path: remote has no '$branch' branch yet -- nothing to add"
      return 0
    fi
    log_step "$path: remote has no '$branch' branch yet -- using its '$base_branch' branch; your first push creates '$branch'"
    branch="$base_branch"
  fi

  classify_subtree "$path" "$branch"

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
