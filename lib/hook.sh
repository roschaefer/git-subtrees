# Assumes lib/common.sh is already sourced.

usage_install_hook() {
  cat <<'EOF'
usage: git subtrees install-hook [--print]

Installs a pre-push hook that refuses to push the monorepo to a subtree
remote, e.g. a plain 'git push vendor/foo main' by mistake, and lists the
subtree remotes it protects. It refuses any commit that has a folder named
like the remote it's pushed to: by the contract that makes it a monorepo
commit, not the subtree's own history. 'git subtrees push' and 'git subtree
push' only send the subtree's own history, so they still work.

The hook lives in the repository's hooks folder (core.hooksPath, if set),
so it protects every worktree, but not other clones: run install-hook once
per clone. 'status' and 'init' remind you while it's missing or outdated.

If a pre-push hook that git-subtrees didn't write already exists,
install-hook leaves it alone and fails. To keep yours, add the hook that
--print shows to it. 'status' and 'init' recognize it by its second line.

A subtree whose own content has a folder named like its path (e.g. a
subtree 'lib' with a 'lib/' folder) can't be pushed with the hook. Push it
with 'git push --no-verify', which skips the hook.

Options:
  --print   print the hook instead of installing it
EOF
}

PRE_PUSH_HOOK_MARKER="# git-subtrees pre-push hook"

# Plain sh, not bash: git runs hooks with whatever shell a GUI or IDE finds,
# which on macOS may be Bash 3.2.
pre_push_hook_body() {
  cat <<'EOF'
#
# Written by 'git subtrees install-hook'. Refuses to push a commit that has
# a folder named like the remote it's pushed to: a subtree remote is named
# after its folder, so that commit holds the monorepo, not the subtree's
# own history.

remote=$1
if ! git remote get-url -- "$remote" >/dev/null 2>&1; then
  cat >/dev/null
  exit 0 # pushing to a URL, not to a remote
fi

refused=0
while read -r local_ref local_oid _; do
  case $local_oid in
    *[!0]*) ;;
    *) continue ;; # deleting a branch
  esac
  # Commits the remote already has were published before; checking them
  # again would only cost time.
  commit=$(
    git rev-list "$local_oid" --not --remotes="$remote" |
      while read -r c; do printf '%s:%s %s\n' "$c" "$remote" "$c"; done |
      git cat-file --batch-check='%(objecttype) %(rest)' |
      sed -n 's/^tree //p' | head -n 1
  )
  if [ -n "$commit" ]; then
    printf "!!   refusing to push %s to '%s': commit %s has a folder '%s/', so it's the monorepo, not the subtree\n" \
      "$local_ref" "$remote" "$commit" "$remote" >&2
    refused=1
  fi
done

if [ "$refused" = 1 ]; then
  printf '%s\n' \
    "!!   push subtree changes with 'git subtrees push' instead" \
    "!!   if the subtree itself has a folder named like its path, push with --no-verify" >&2
  exit 1
fi
EOF
}

# The marker line carries a checksum of the body: it tells this version's
# hook from an earlier one, even inside a hook the user combined with their
# own, and a hook that is only an earlier version's from an edited one.
pre_push_hook_marker() {
  printf '%s %s\n' "$PRE_PUSH_HOOK_MARKER" "$(pre_push_hook_body | cksum | cut -d' ' -f1)"
}

pre_push_hook() {
  echo '#!/bin/sh'
  pre_push_hook_marker
  pre_push_hook_body
}

# Prints the path of the pre-push hook: in the common git dir, so it's the
# same for every worktree, or in core.hooksPath if that's set.
pre_push_hook_path() {
  printf '%s/pre-push\n' "$(git rev-parse --git-path hooks)"
}

# Succeeds if hook $1 is an unedited hook of some git-subtrees version,
# which install-hook may replace without losing anything.
is_plain_pre_push_hook() {
  local hook="$1" marker sum
  marker="$(sed -n 2p "$hook")"
  [[ "$marker" == "$PRE_PUSH_HOOK_MARKER "* ]] || return 1
  sum="$(tail -n +3 "$hook" | cksum | cut -d' ' -f1)"
  [[ "$marker" == "$PRE_PUSH_HOOK_MARKER $sum" ]]
}

# Prints the state of the pre-push hook at $1: missing, current (it runs
# this version's check), outdated (an unedited earlier version's hook, or
# not executable) or foreign (anything else, which install-hook won't touch).
pre_push_hook_state() {
  local hook="$1"
  if [[ ! -e "$hook" ]]; then
    echo missing
  elif [[ -x "$hook" ]] && grep -qxF "$(pre_push_hook_marker)" "$hook"; then
    echo current
  elif is_plain_pre_push_hook "$hook"; then
    echo outdated
  else
    echo foreign
  fi
}

cmd_install_hook() {
  case "${1:-}" in
    -h | --help)
      usage_install_hook
      exit 0
      ;;
    --print)
      pre_push_hook
      exit 0
      ;;
    "") ;;
    *)
      usage_install_hook >&2
      exit 1
      ;;
  esac

  cd_to_repo_root
  discover_subtrees
  local hook
  hook="$(pre_push_hook_path)"
  case "$(pre_push_hook_state "$hook")" in
    current)
      log_ok "pre-push hook already installed: $hook"
      ;;
    missing | outdated)
      mkdir -p "$(dirname "$hook")"
      pre_push_hook >"$hook"
      chmod +x "$hook"
      log_ok "installed pre-push hook: $hook"
      ;;
    foreign)
      die "$hook already exists and isn't git-subtrees' own -- see 'git subtrees install-hook -h' to combine the two"
      ;;
  esac

  local path
  for path in "${ALL_PATHS[@]}"; do
    log_ok "$path: protected from a plain 'git push' of the monorepo"
  done
  log_ok "subtrees you add later are protected too"
}

# For status and init: points out that the pre-push hook doesn't protect
# the subtree remotes, and what to do about it.
hint_pre_push_hook() {
  local hook
  hook="$(pre_push_hook_path)"
  case "$(pre_push_hook_state "$hook")" in
    current) ;;
    missing)
      log_warn "a plain 'git push' can send the monorepo to a subtree remote -- run 'git subtrees install-hook' to refuse that"
      ;;
    outdated)
      log_warn "$hook is from another git-subtrees version -- run 'git subtrees install-hook' to update it"
      ;;
    foreign)
      log_warn "$hook doesn't refuse a plain 'git push' of the monorepo to a subtree remote -- see 'git subtrees install-hook -h'"
      ;;
  esac
}
