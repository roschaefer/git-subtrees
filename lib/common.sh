# Shared discovery, classification, and logging helpers.
# Sourced first by the entrypoint; every other lib/*.sh file assumes these
# are already in scope.

declare -ga ALL_REMOTES=()
declare -ga ALL_PATHS=()

# Every subtree path/remote-mapping check, and every git-subtree invocation
# (--prefix=<path>, HEAD:<path>, etc.), is only meaningful relative to the
# repo root. Without this, running any command from inside a subtree
# directory (or any other subdirectory) makes every remote look unmapped,
# since worktree directory names are then resolved against the wrong cwd.
cd_to_repo_root() {
  local toplevel
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
  cd "$toplevel" || die "failed to cd to repo root: $toplevel"
}

log_ok() { printf 'ok   %s\n' "$*"; }
log_warn() { printf '??   %s\n' "$*" >&2; }
log_err() { printf '!!   %s\n' "$*" >&2; }
log_step() { printf '===  %s\n' "$*"; }
die() {
  log_err "$*"
  exit 1
}

# Prints the current local branch name; dies on detached HEAD, since the
# whole tool relies on "current branch name" as the sync target.
current_branch() {
  local branch
  branch="$(git symbolic-ref --quiet --short HEAD)" ||
    die "not on a branch (detached HEAD) -- git subtrees requires a named branch"
  printf '%s\n' "$branch"
}

# Populates ALL_REMOTES (every git remote) and ALL_PATHS (the subset whose
# name matches an existing worktree directory). This *is* the entire
# subtree-discovery mechanism -- there is no config file.
discover_subtrees() {
  ALL_REMOTES=()
  ALL_PATHS=()
  local remote
  while IFS= read -r remote; do
    [[ -n "$remote" ]] || continue
    ALL_REMOTES+=("$remote")
    if [[ -d "$remote" ]]; then
      ALL_PATHS+=("$remote")
    fi
  done < <(git remote)
}

is_subtree_path() {
  local path="$1" p
  for p in "${ALL_PATHS[@]}"; do
    [[ "$p" == "$path" ]] && return 0
  done
  return 1
}

target_ref_for() {
  printf 'refs/remotes/%s/%s\n' "$1" "$2"
}

# False for a name starting with '-'. git-subtree's own OPTS_SPEC parsing
# (git rev-parse --parseopt) matches a handful of dash-prefixed values as
# its own flags no matter where they appear (-h/--help, -q/--quiet, ...),
# and --prefix's value separately reaches an internal `dirname` call that
# rejects any leading '-' outright (verified against the installed
# git-subtree contrib script). Both make `git subtree add/pull/push
# --prefix=<name>` unusable for such a name, regardless of "--" at this
# wrapper's own call sites -- see fix(cli): terminate options before
# remote-name arguments. The same parsing applies to the branch argument
# git-subtree takes, not just --prefix/REPOSITORY, so init/pull/push check
# both the path and the current branch before invoking git-subtree, and do
# so upfront (before any other state-dependent branching) so the failure is
# a clear, early error instead of a confusing crash partway through
# (fetch/status have no such restriction, since they only ever call plain
# git builtins).
usable_with_git_subtree() {
  [[ "$1" != -* ]]
}

regex_escape() {
  printf '%s' "$1" | sed -e 's/[.[\*^$()+?{}|\\]/\\&/g'
}

# Most recent commit reachable from HEAD carrying a
# "git-subtree-dir: <path>" trailer -- this is the squash commit `git
# subtree add`/`pull --squash` created the last time this path was synced.
# Not path-limited: the squash commit's own tree has no prefix, so a
# pathspec-limited `git log` would never match it (git log's history
# simplification also hides it behind the merge commit). Empty output means
# this path has never been initialized via `git subtree add`/`pull`.
find_sync_commit() {
  local path="$1" pattern
  pattern="^git-subtree-dir: $(regex_escape "$path")\$"
  git log --format=%H --extended-regexp --grep="$pattern" -1 2>/dev/null || true
}

# Extracts the upstream commit SHA a sync commit (see find_sync_commit)
# recorded via its "git-subtree-split: <sha>" trailer.
sync_split_sha() {
  git show -s --format=%B "$1" | sed -n 's/^git-subtree-split: *//p' | tail -1
}

# The commit reachable from HEAD whose parent list includes the given sync
# commit -- i.e. the merge/add commit that brought that squash in, and the
# point after which "local changes under path" are measured.
find_merge_commit_for_sync() {
  local sync_commit="$1"
  git rev-list --ancestry-path "$sync_commit..HEAD" --parents | awk -v s="$sync_commit" \
    'found {next} {for (i=2;i<=NF;i++) if ($i==s) {print $1; found=1; next}}'
}

# Classifies subtree <path>'s sync state against remote <path>'s <branch>.
# Sets SUBTREE_STATE, SUBTREE_TARGET_REF, SUBTREE_URL as globals rather than
# returning a value, since callers (status, push, pull) need all three.
#
# SUBTREE_STATE is one of:
#   not-connected     remote has never been fetched (no tracking refs at all)
#   missing-at-head    remote has been fetched, but has no <branch> ref
#   up-to-date          local path tree already matches remote tree
#   push                 only local has changed since the last sync
#   pull                 only remote has changed since the last sync
#   diverged             both changed, but share a common sync point
#   unrelated-history    both changed (or never synced), and share NO common
#                         ancestor -- pull/push must not auto-merge this
#
# Squash-based subtrees never make the raw remote commit an ancestor of
# HEAD, so plain `git merge-base HEAD <target-ref>` is useless here. Instead
# this reconstructs the last sync point from git-subtree's own
# git-subtree-dir/git-subtree-split commit trailers, then compares real
# remote commits (split_sha vs target_ref) via merge-base, and compares
# local content (path tree at the sync commit vs at HEAD) via diff.
classify_subtree() {
  local path="$1" branch="$2" remote="$1"
  SUBTREE_STATE=""
  SUBTREE_TARGET_REF=""
  SUBTREE_URL="$(git remote get-url -- "$remote" 2>/dev/null || true)"

  if [[ -z "$(git for-each-ref "refs/remotes/$remote/")" ]]; then
    SUBTREE_STATE="not-connected"
    return
  fi

  local target_ref
  target_ref="$(target_ref_for "$remote" "$branch")"
  SUBTREE_TARGET_REF="$target_ref"

  if ! git show-ref --verify --quiet "$target_ref"; then
    SUBTREE_STATE="missing-at-head"
    return
  fi

  local remote_tree local_tree
  remote_tree="$(git rev-parse "${target_ref}^{tree}")"
  local_tree="$(git rev-parse "HEAD:$path" 2>/dev/null || true)"

  if [[ -n "$local_tree" && "$local_tree" == "$remote_tree" ]]; then
    SUBTREE_STATE="up-to-date"
    return
  fi

  local sync_commit
  sync_commit="$(find_sync_commit "$path")"

  if [[ -z "$sync_commit" ]]; then
    SUBTREE_STATE="unrelated-history"
    return
  fi

  local split_sha merge_commit
  split_sha="$(sync_split_sha "$sync_commit")"
  merge_commit="$(find_merge_commit_for_sync "$sync_commit")"

  local local_changed=1
  if [[ -n "$merge_commit" ]] && git diff --quiet "$merge_commit" HEAD -- "$path"; then
    local_changed=0
  fi

  local remote_changed=1
  if git cat-file -e "${split_sha}^{commit}" 2>/dev/null; then
    if git merge-base --is-ancestor "$split_sha" "$target_ref" 2>/dev/null; then
      local split_tree
      split_tree="$(git rev-parse "${split_sha}^{tree}")"
      [[ "$split_tree" == "$remote_tree" ]] && remote_changed=0
    elif ! git merge-base "$split_sha" "$target_ref" >/dev/null 2>&1; then
      SUBTREE_STATE="unrelated-history"
      return
    fi
  fi

  if ((local_changed && remote_changed)); then
    SUBTREE_STATE="diverged"
  elif ((remote_changed)); then
    SUBTREE_STATE="pull"
  elif ((local_changed)); then
    SUBTREE_STATE="push"
  else
    SUBTREE_STATE="up-to-date"
  fi
}

# Prints manual recovery commands for a subtree in the "unrelated-history"
# state. There's no principled automatic merge when local and remote share
# no common ancestor -- only a human decision to keep one side and discard
# the other's history. Both command sequences are verified to work: the
# first re-adopts the remote wholesale (same shape as a fresh `init`), the
# second force-pushes the local content as the remote's new history (a
# split + force-pushed ref update, since `git subtree push` has no force
# flag of its own).
print_unrelated_history_guidance() {
  local path="$1" branch="$2"
  local tmp_branch="tmp-split-$(basename "$path")"
  log_warn "$path: remote and local share no history -- pick one side manually:"
  cat >&2 <<EOF

  # accept the remote's version, discarding local changes under $path:
  git rm -r $path
  git commit -m "remove $path before re-adopting from remote '$path'"
  git subtree add --prefix=$path $path $branch --squash

  # OR: accept the local (monorepo) version, overwriting $path's history:
  git subtree split --prefix=$path -b $tmp_branch
  git push --force $path $tmp_branch:$branch
  git branch -D $tmp_branch

EOF
}
