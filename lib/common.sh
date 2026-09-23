# Shared discovery, classification, and logging helpers.
# Sourced first by the entrypoint; every other lib/*.sh file assumes these
# are already in scope.

declare -ga ALL_REMOTES=()
declare -ga ALL_PATHS=()
# Results of parse_base_args.
declare -g BASE_ARG=""
declare -ga PATH_ARGS=()

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

# Shared option parsing for the commands that take `[--base <branch>]
# [path...]` (diff, push, status). Sets BASE_ARG and PATH_ARGS. $1 names the
# command's usage function, which is run (then exit 0) for -h/--help; the
# remaining arguments are the command line. Everything after `--`, and any
# other argument, is a path -- so a subtree named like a flag still works.
parse_base_args() {
  local usage_fn="$1"
  shift
  BASE_ARG=""
  PATH_ARGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        "$usage_fn"
        exit 0
        ;;
      --base)
        [[ $# -ge 2 && -n "$2" ]] || die "--base needs a branch name"
        BASE_ARG="$2"
        shift
        ;;
      --base=*)
        BASE_ARG="${1#--base=}"
        [[ -n "$BASE_ARG" ]] || die "--base needs a branch name"
        ;;
      --)
        shift
        PATH_ARGS+=("$@")
        break
        ;;
      *)
        PATH_ARGS+=("$1")
        ;;
    esac
    shift
  done
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

  local path other
  for path in "${ALL_PATHS[@]}"; do
    if other="$(overlapping_remote "$path")"; then
      die_nested "$path" "$other"
    fi
  done
}

# Prints the first remote in ALL_REMOTES nested inside, or containing, $1.
# Git 2.51+ refuses such remote names, older versions accept them.
overlapping_remote() {
  local name="$1" remote
  for remote in "${ALL_REMOTES[@]}"; do
    if [[ "$remote" == "$name"/* || "$name" == "$remote"/* ]]; then
      printf '%s\n' "$remote"
      return 0
    fi
  done
  return 1
}

# Nested subtrees are refused outright rather than half-supported: the outer
# subtree's content includes the inner one, so it can never match its own
# remote, and its tracking refs (refs/remotes/<outer>/*) include the inner
# remote's. Every state reported for it would be wrong, and the recovery
# commands printed for unrelated history would delete or publish the inner
# subtree. The inner remote corrupts the outer's refs even without a folder
# of its own, so any remote overlapping a subtree path counts.
#
# Prints "'<outer>' and '<inner>'" for two overlapping names, in that order.
overlap_pair() {
  if [[ "$2" == "$1"/* ]]; then
    printf "'%s' and '%s'" "$1" "$2"
  else
    printf "'%s' and '%s'" "$2" "$1"
  fi
}

# `git remote remove <inner>` keeps the inner remote's tracking refs, since
# the outer remote's fetch refspec covers them too; they would then look like
# branches of the outer remote. Removing the outer remote leaves nothing
# behind.
die_nested() {
  local outer="$1" inner="$2"
  if [[ "$outer" == "$inner"/* ]]; then
    outer="$2"
    inner="$1"
  fi
  local q_outer q_inner q_refs
  q_outer="$(shell_quote "$outer")"
  q_inner="$(shell_quote "$inner")"
  q_refs="$(shell_quote "refs/remotes/$inner/")"
  log_err "nested subtrees are not supported: $(overlap_pair "$outer" "$inner") overlap -- fix it with one of:"
  cat >&2 <<EOF

  git remote remove $q_outer

  git remote remove $q_inner
  git for-each-ref --format='delete %(refname)' $q_refs | git update-ref --no-deref --stdin

EOF
  exit 1
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
# git-subtree contrib script). Both make `git subtree add/merge/push
# --prefix=<name>` unusable for such a name, regardless of "--" at this
# wrapper's own call sites -- see fix(cli): terminate options before
# remote-name arguments. The same parsing applies to the branch argument
# git-subtree takes, not just --prefix/REPOSITORY, so init/pull/push check
# both the path and the current branch before invoking git-subtree, and do
# so upfront (before any other state-dependent branching) so the failure is
# a clear, early error instead of a confusing crash partway through
# (fetch/prune/status have no such restriction, since they only ever call
# plain git builtins).
usable_with_git_subtree() {
  [[ "$1" != -* ]]
}

# Prints $1 as one shell word for a ready-to-run command we print: as-is if
# it only has characters no shell treats specially, else single-quoted. Git
# accepts shell metacharacters in remote and branch names (e.g. "x;id"), so
# every name in a printed command goes through this.
shell_quote() {
  if [[ "$1" =~ ^[A-Za-z0-9_./:@%+=,-]+$ ]]; then
    printf '%s' "$1"
  else
    printf "'%s'" "${1//\'/\'\\\'\'}"
  fi
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

# Prints the full ref of the monorepo's base branch -- the branch feature
# branches are cut from -- or fails if there is none. Git doesn't record
# which branch a branch was cut from, so this is resolved, in order, from:
#   1. the explicit branch given as $1 (from --base), which always wins;
#   2. the target of refs/remotes/origin/HEAD, if the monorepo has one;
#   3. `git config init.defaultBranch`.
# A name may be a local branch ("main"), a remote-tracking one
# ("origin/main") or a full ref. A candidate only counts if it exists and
# shares history with HEAD. There is deliberately no guessing at
# "main"/"master": callers ask the user for --base instead.
#
# When a name matches both a local branch and origin/<name>, the one whose
# merge base with HEAD is more recent wins, so a stale local branch can't
# hide the fresher origin/<name> a branch was actually cut from.
resolve_base_ref() {
  local explicit="${1:-}" candidates=() candidate ref refs mb best_ref="" best_mb="" origin_head
  if [[ -n "$explicit" ]]; then
    candidates+=("$explicit")
  else
    origin_head="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    [[ -n "$origin_head" ]] && candidates+=("${origin_head#origin/}")
    candidate="$(git config --get init.defaultBranch 2>/dev/null || true)"
    [[ -n "$candidate" ]] && candidates+=("$candidate")
  fi
  for candidate in "${candidates[@]}"; do
    refs=("refs/heads/$candidate" "refs/remotes/$candidate" "refs/remotes/origin/$candidate")
    [[ "$candidate" == refs/* ]] && refs=("$candidate")
    for ref in "${refs[@]}"; do
      git show-ref --verify --quiet "$ref" || continue
      mb="$(git merge-base HEAD "$ref" 2>/dev/null)" || continue
      if [[ -z "$best_ref" ]] || { [[ "$mb" != "$best_mb" ]] && git merge-base --is-ancestor "$best_mb" "$mb"; }; then
        best_ref="$ref"
        best_mb="$mb"
      fi
    done
    [[ -n "$best_ref" ]] && break
  done
  [[ -n "$best_ref" ]] || return 1
  printf '%s\n' "$best_ref"
}

# For a subtree whose remote has no branch like the current one: has <path>
# changed on this branch, compared with the monorepo's base branch? Judged
# purely inside the monorepo -- nothing on the remote is consulted -- from
# the merge base of HEAD and the base branch, so later changes on the base
# branch don't count against this one. Sets:
#   SUBTREE_CHANGES_VS_BASE  yes | no | unresolved (no usable base branch)
#                            | self (the current branch is the base branch)
#                            | error (git could not compare)
#   SUBTREE_BASE_REF         the resolved base ref (empty if unresolved)
#   SUBTREE_BASE_BRANCH      its short name, for messages
#   SUBTREE_BASE_MERGE_BASE  the merge base commit (yes/no only)
# $2 is an explicit --base branch, if any.
changes_vs_base() {
  local path="$1" explicit="${2:-}" head_ref rc
  SUBTREE_CHANGES_VS_BASE="unresolved"
  SUBTREE_BASE_REF=""
  SUBTREE_BASE_BRANCH=""
  SUBTREE_BASE_MERGE_BASE=""

  SUBTREE_BASE_REF="$(resolve_base_ref "$explicit")" || {
    SUBTREE_BASE_REF=""
    return 0
  }
  SUBTREE_BASE_BRANCH="${SUBTREE_BASE_REF#refs/heads/}"
  SUBTREE_BASE_BRANCH="${SUBTREE_BASE_BRANCH#refs/remotes/}"

  head_ref="$(git symbolic-ref --quiet HEAD 2>/dev/null || true)"
  if [[ "$SUBTREE_BASE_REF" == "$head_ref" ]]; then
    SUBTREE_CHANGES_VS_BASE="self"
    return 0
  fi

  SUBTREE_BASE_MERGE_BASE="$(git merge-base HEAD "$SUBTREE_BASE_REF")"
  # `git diff --quiet` exits 1 for "differs" and >1 for a real failure; only
  # the former may be read as "changed", or an error would create a branch.
  if git diff --quiet "$SUBTREE_BASE_MERGE_BASE" HEAD -- "$path" 2>/dev/null; then
    SUBTREE_CHANGES_VS_BASE="no"
  else
    rc=$?
    if ((rc == 1)); then
      SUBTREE_CHANGES_VS_BASE="yes"
    else
      SUBTREE_CHANGES_VS_BASE="error"
    fi
  fi
}

# Prints the tree of the newest commit on <target-ref> since <split-sha>
# that is our own push: the commit `git subtree split` made from a local
# commit since <sync-commit>. Fails if there is none. A push doesn't move
# the sync point, so this is where both sides last agreed if we pushed
# since. split copies each commit's author, dates and message, and gives it
# <path>'s tree at that commit; someone else's commit, even with the same
# content, won't match all of these.
own_pushed_tree() {
  local path="$1" sync_commit="$2" split_sha="$3" target_ref="$4"
  local -A local_commits=()
  local commit tree sig
  while IFS=' ' read -r commit sig; do
    local_commits["$sig"]+="$commit "
  done < <(git log --full-history --ancestry-path --format='%H %at %ct %ae %s' \
    "$sync_commit..HEAD" -- "$path")
  ((${#local_commits[@]})) || return 1

  while IFS=' ' read -r tree sig; do
    for commit in ${local_commits["$sig"]:-}; do
      if [[ "$(git rev-parse --quiet --verify "$commit:$path")" == "$tree" ]]; then
        printf '%s\n' "$tree"
        return 0
      fi
    done
  done < <(git log --format='%T %at %ct %ae %s' "$split_sha..$target_ref")
  return 1
}

# Classifies subtree <path>'s sync state against remote <path>'s <branch>.
# Sets SUBTREE_STATE, SUBTREE_TARGET_REF, SUBTREE_URL, SUBTREE_SPLIT_SHA as
# globals rather than returning a value, since callers (status, push, pull)
# need them.
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
  SUBTREE_SPLIT_SHA=""
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

  local split_sha
  split_sha="$(sync_split_sha "$sync_commit")"
  SUBTREE_SPLIT_SHA="$split_sha"

  # Local changes are measured against the squash commit's own tree -- the
  # remote content it recorded -- not against the merge commit that brought
  # it in: after pulling a divergence that merge already contains the local
  # changes, which would hide them from push.
  local local_changed=1
  if [[ "$local_tree" == "$(git rev-parse "${sync_commit}^{tree}")" ]]; then
    local_changed=0
  fi

  local remote_changed=1
  if git cat-file -e "${split_sha}^{commit}" 2>/dev/null; then
    if git merge-base --is-ancestor "$split_sha" "$target_ref" 2>/dev/null; then
      local split_tree
      split_tree="$(git rev-parse "${split_sha}^{tree}")"
      [[ "$split_tree" == "$remote_tree" ]] && remote_changed=0
      # A push doesn't move the sync point, so after one the remote looks
      # changed. If it holds our own push, compare both sides with that
      # instead: it's where they last agreed.
      local pushed_tree
      if ((remote_changed)) && pushed_tree="$(own_pushed_tree "$path" "$sync_commit" "$split_sha" "$target_ref")"; then
        [[ "$remote_tree" == "$pushed_tree" ]] && remote_changed=0
        local_changed=1
        [[ "$local_tree" == "$pushed_tree" ]] && local_changed=0
      fi
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
  local q_path q_branch q_tmp q_msg q_refspec
  q_path="$(shell_quote "$path")"
  q_branch="$(shell_quote "$branch")"
  q_tmp="$(shell_quote "$tmp_branch")"
  q_msg="$(shell_quote "remove $path before re-adopting it from its remote")"
  q_refspec="$(shell_quote "$tmp_branch:$branch")"
  log_warn "$path: remote and local share no history -- pick one side manually:"
  cat >&2 <<EOF

  # accept the remote's version, discarding local changes under $path:
  git rm -r $q_path
  git commit -m $q_msg
  git subtree add --prefix=$q_path $q_path $q_branch --squash

  # OR: accept the local (monorepo) version, overwriting $path's history:
  git subtree split --prefix=$q_path -b $q_tmp
  git push --force $q_path $q_refspec
  git branch -D $q_tmp

EOF
}
