# Bash completion for git-subtrees.
#
# Works both as a `git subtrees ...` completion (git-completion.bash
# dispatches to a function named _git_subtrees for the "subtrees"
# subcommand) and as a standalone completion for the git-subtrees
# executable itself, so it's safe to source unconditionally.
#
# Install (pick one):
#   source /path/to/git-subtrees.bash        # e.g. from ~/.bashrc
#   cp /path/to/git-subtrees.bash /etc/bash_completion.d/git-subtrees

# Subtree paths: git remotes whose name matches an existing directory.
# Mirrors discover_subtrees() in lib/common.sh.
__git_subtrees_paths() {
  local remote
  while IFS= read -r remote; do
    [[ -n "$remote" && -d "$remote" ]] && printf '%s\n' "$remote"
  done < <(git remote 2>/dev/null)
}

_git_subtrees() {
  local cur start cmd
  cur="${COMP_WORDS[COMP_CWORD]}"

  # Skip past "git subtrees" when dispatched by git-completion.bash, or
  # just "git-subtrees" when this command is completed directly.
  start=1
  [[ "${COMP_WORDS[0]}" == git ]] && start=2

  if ((COMP_CWORD == start)); then
    mapfile -t COMPREPLY < <(compgen -W "init fetch pull prune push status -h --help" -- "$cur")
    return
  fi

  cmd="${COMP_WORDS[start]}"
  case "$cmd" in
    fetch | pull)
      mapfile -t COMPREPLY < <(compgen -W "$(__git_subtrees_paths) -h --help" -- "$cur")
      ;;
    push | status)
      if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == --base ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null)" -- "$cur")
      else
        mapfile -t COMPREPLY < <(compgen -W "$(__git_subtrees_paths) --base -h --help" -- "$cur")
      fi
      ;;
    prune)
      mapfile -t COMPREPLY < <(compgen -W "$(__git_subtrees_paths) -n --dry-run -h --help" -- "$cur")
      ;;
    init)
      if ((COMP_CWORD == start + 1)); then
        mapfile -t COMPREPLY < <(compgen -d -- "$cur")
      fi
      ;;
    *) ;;
  esac
}

complete -o bashdefault -o default -F _git_subtrees git-subtrees 2>/dev/null
