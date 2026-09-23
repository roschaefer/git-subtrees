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

# Counts the positional arguments before the word being completed, skipping
# options and --base's value (bash may split "--base=main" into "--base",
# "=" and "main"). $1 is the index of the subcommand in COMP_WORDS.
__git_subtrees_positionals() {
  local i count=0
  for ((i = $1 + 1; i < COMP_CWORD; i++)); do
    case "${COMP_WORDS[i]}" in
      --base)
        [[ "${COMP_WORDS[i + 1]:-}" == = ]] && ((i++))
        ((i++))
        ;;
      -*) ;;
      *) ((count++)) ;;
    esac
  done
  printf '%s\n' "$count"
}

_git_subtrees() {
  local cur start cmd
  cur="${COMP_WORDS[COMP_CWORD]}"

  # Skip past "git subtrees" when dispatched by git-completion.bash, or
  # just "git-subtrees" when this command is completed directly.
  start=1
  [[ "${COMP_WORDS[0]}" == git ]] && start=2

  if ((COMP_CWORD == start)); then
    mapfile -t COMPREPLY < <(compgen -W "diff init fetch merge pull prune push status -h --help" -- "$cur")
    return
  fi

  cmd="${COMP_WORDS[start]}"
  case "$cmd" in
    fetch | merge | pull)
      mapfile -t COMPREPLY < <(compgen -W "$(__git_subtrees_paths) -h --help" -- "$cur")
      ;;
    diff | push | status)
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
      if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == --base ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null)" -- "$cur")
      elif [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "--base -h --help" -- "$cur")
      elif (($(__git_subtrees_positionals "$start") == 0)); then
        mapfile -t COMPREPLY < <(compgen -d -- "$cur")
      fi
      ;;
    *) ;;
  esac
}

complete -o bashdefault -o default -F _git_subtrees git-subtrees 2>/dev/null
