#compdef git-subtrees
# Zsh completion for git-subtrees.
#
# Install into a directory on your $fpath as `_git-subtrees` (the leading
# underscore and hyphen are the convention zsh's own `_git` uses to find
# completions for third-party "git-<name>" subcommands, and are also what
# lets this file complete the standalone git-subtrees executable via
# #compdef above):
#
#   ln -s /path/to/git-subtrees.zsh /usr/local/share/zsh/site-functions/_git-subtrees
#
# Then start a new shell (or run `compinit`).

# Subtree paths: git remotes whose name matches an existing directory.
# Mirrors discover_subtrees() in lib/common.sh.
__git_subtrees_paths() {
  local remote
  git remote 2>/dev/null | while IFS= read -r remote; do
    [[ -n "$remote" && -d "$remote" ]] && print -r -- "$remote"
  done
}

_git-subtrees() {
  local curcontext="$curcontext" state line
  local -a commands paths

  commands=(
    'init:one-time bootstrap of a path/url pair'
    'fetch:fetch every subtree'\''s remote'
    'pull:squash-merge upstream changes into subtree paths'
    'prune:prune stale remote-tracking refs'
    'push:push local subtree changes upstream'
    'status:show sync state of every remote'
  )

  if ((CURRENT == 2)); then
    _describe -t commands 'git subtrees command' commands
    return
  fi

  case ${words[2]} in
    fetch | pull)
      paths=("${(@f)$(__git_subtrees_paths)}")
      _describe -t paths 'subtree path' paths
      ;;
    push | status)
      paths=("${(@f)$(__git_subtrees_paths)}")
      _arguments \
        '--base=[monorepo base branch to compare against]:branch:__git_branch_names' \
        '(-h --help)'{-h,--help}'[show usage]' \
        '*:subtree path:->paths'
      if [[ $state == paths ]]; then
        _describe -t paths 'subtree path' paths
      fi
      ;;
    prune)
      paths=("${(@f)$(__git_subtrees_paths)}")
      _arguments \
        '(-n --dry-run)'{-n,--dry-run}'[show stale refs without pruning]' \
        '(-h --help)'{-h,--help}'[show usage]' \
        '*:subtree path:->paths'
      if [[ $state == paths ]]; then
        _describe -t paths 'subtree path' paths
      fi
      ;;
    init)
      if ((CURRENT == 3)); then
        _files -/
      fi
      ;;
  esac
}

_git-subtrees "$@"
