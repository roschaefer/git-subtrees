# Assumes lib/common.sh is already sourced.

usage_status() {
  cat <<EOF
usage: git subtrees status [--base <branch>] [path...]

Shows the sync state of every subtree, plus every registered remote that
has no matching directory ([no mapping]). Purely local -- run 'git subtrees
fetch' first for up-to-date results. Defaults to every discovered subtree
when no paths are given.

For a subtree whose remote has no branch named like the current one, the
state is whether the subtree changed on this branch compared with the
monorepo's base branch (--base, else origin/HEAD, else init.defaultBranch).

Each subtree is marked [push-protected] or [NOT push-protected]. A plain
'git push' to a remote that isn't protected sends the whole monorepo there.
A remote without a push URL of its own, and with a single URL, can be
protected like 'git subtrees init' does:

  git remote set-url --push <path> $(shell_quote "$PUSH_PROTECTED_URL")
EOF
}

status_warn() { printf '??   %s\n' "$*"; }

# Whether status colors its output, like Git colors `git status` (color.status,
# else color.ui; by default only on a terminal). Set by cmd_status, before any
# output goes through a command substitution, where stdout is never a terminal.
declare -g STATUS_COLOR=false

set_status_color() {
  local tty=false
  [[ -t 1 ]] && tty=true
  STATUS_COLOR="$(git config --get-colorbool color.status "$tty")"
}

# Prints "$1$2$3", with ANSI codes $1 and $3 only if STATUS_COLOR is true.
colorize() {
  if [[ "$STATUS_COLOR" == true ]]; then
    printf '%s%s%s' "$1" "$2" "$3"
  else
    printf '%s' "$2"
  fi
}

# Prints subtree path $1 followed by whether its remote is push-protected.
subtree_label() {
  if is_push_protected "$1"; then
    printf '%s [push-protected]' "$1"
  else
    printf '%s %s' "$1" "$(colorize $'\e[31m' '[NOT push-protected]' $'\e[m')"
  fi
}

# Prints the status of a subtree whose remote has no branch like the current
# one: what changed on this branch compared with the monorepo's base branch.
format_missing_branch_line() {
  local path="$1" branch="$2" base="$3"
  changes_vs_base "$path" "$base"
  case "$SUBTREE_CHANGES_VS_BASE" in
    no)
      log_ok "$(subtree_label "$path") (no '$branch' branch on remote; unchanged since '$SUBTREE_BASE_BRANCH')"
      ;;
    yes)
      log_ok "$(subtree_label "$path") (no '$branch' branch on remote; changed since '$SUBTREE_BASE_BRANCH' -- push would create it)"
      git --no-pager diff --stat "$SUBTREE_BASE_MERGE_BASE" HEAD -- "$path" 2>/dev/null || true
      ;;
    self)
      status_warn "$(subtree_label "$path") (remote has no '$branch' branch)"
      ;;
    error)
      status_warn "$(subtree_label "$path") (no '$branch' branch on remote; could not compare with base branch '$SUBTREE_BASE_BRANCH')"
      ;;
    unresolved)
      if [[ -n "$base" ]]; then
        status_warn "$(subtree_label "$path") (no '$branch' branch on remote; base branch '$base' not found, or it shares no history)"
      else
        status_warn "$(subtree_label "$path") (no '$branch' branch on remote; monorepo base branch unknown -- pass --base <branch>)"
      fi
      ;;
  esac
}

# Classifies and prints the status of one subtree path.
format_status_line() {
  local path="$1" branch="$2" base="${3:-}"
  classify_subtree "$path" "$branch"

  case "$SUBTREE_STATE" in
    not-connected)
      status_warn "$(subtree_label "$path") (never fetched -- run 'git subtrees fetch $path')"
      ;;
    missing-at-head)
      format_missing_branch_line "$path" "$branch" "$base"
      ;;
    up-to-date)
      log_ok "$(subtree_label "$path") (up to date)"
      ;;
    push | pull | diverged)
      log_ok "$(subtree_label "$path") ($SUBTREE_STATE)"
      local local_tree
      local_tree="$(git rev-parse "HEAD:$path" 2>/dev/null || true)"
      # Diff order follows what the pending operation would apply, so
      # insertions in the diffstat always mean "content gained": push
      # diffs remote->local (what push would add to remote), pull diffs
      # local->remote (what pull would add to local). diverged has no
      # single right direction; remote->local is picked for consistency.
      case "$SUBTREE_STATE" in
        pull) git --no-pager diff --stat "$local_tree" "$SUBTREE_TARGET_REF" 2>/dev/null || true ;;
        *) git --no-pager diff --stat "$SUBTREE_TARGET_REF" "$local_tree" 2>/dev/null || true ;;
      esac
      ;;
    unrelated-history)
      status_warn "$(subtree_label "$path") (unrelated history -- see 'git subtrees pull $path' for options)"
      ;;
  esac
}

format_unmapped_remote_line() {
  local remote="$1"
  printf '??   %s [no mapping]\n' "$remote"
}

cmd_status() {
  parse_base_args usage_status "$@"
  set_status_color
  local base="$BASE_ARG"
  local paths=("${PATH_ARGS[@]}")

  cd_to_repo_root
  discover_subtrees
  local branch
  branch="$(current_branch)"

  local explicit_paths=0
  if [[ ${#paths[@]} -eq 0 ]]; then
    paths=("${ALL_PATHS[@]}")
  else
    explicit_paths=1
  fi

  local path
  for path in "${paths[@]}"; do
    is_subtree_path "$path" || die "not a subtree path: $path"
  done

  if ((explicit_paths == 0)); then
    local remote
    for remote in "${ALL_REMOTES[@]}"; do
      is_subtree_path "$remote" || format_unmapped_remote_line "$remote"
    done
  fi

  for path in "${paths[@]}"; do
    format_status_line "$path" "$branch" "$base"
  done
}
