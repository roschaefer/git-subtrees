# Fish completion for git-subtrees.
#
# Fish already completes any `git-<name>` executable on $PATH as `git
# <name>` (see __fish_git_custom_commands / __fish_git_complete_custom_command
# in fish's own git completions), delegating to whatever's registered for
# the standalone command. So this file, once installed, completes both
# `git-subtrees ...` and `git subtrees ...`.
#
# Install:
#   ln -s /path/to/git-subtrees.fish ~/.config/fish/completions/git-subtrees.fish

# Subtree paths: git remotes whose name matches an existing directory.
# Mirrors discover_subtrees() in lib/common.sh.
function __git_subtrees_paths
    for remote in (git remote 2>/dev/null)
        if test -d $remote
            echo $remote
        end
    end
end

set -l commands init fetch pull prune push status

complete -c git-subtrees -f

complete -c git-subtrees -n "not __fish_seen_subcommand_from $commands" -a init -d 'bootstrap a path/url pair'
complete -c git-subtrees -n "not __fish_seen_subcommand_from $commands" -a fetch -d "fetch every subtree's remote"
complete -c git-subtrees -n "not __fish_seen_subcommand_from $commands" -a pull -d 'squash-merge upstream changes'
complete -c git-subtrees -n "not __fish_seen_subcommand_from $commands" -a prune -d 'prune stale remote-tracking refs'
complete -c git-subtrees -n "not __fish_seen_subcommand_from $commands" -a push -d 'push local subtree changes'
complete -c git-subtrees -n "not __fish_seen_subcommand_from $commands" -a status -d 'show sync state'
complete -c git-subtrees -n "not __fish_seen_subcommand_from $commands" -s h -l help -d 'show usage'

complete -c git-subtrees -n "__fish_seen_subcommand_from fetch pull push status" -a "(__git_subtrees_paths)" -d 'subtree path'
complete -c git-subtrees -n "__fish_seen_subcommand_from fetch pull push status" -s h -l help -d 'show usage'
complete -c git-subtrees -n "__fish_seen_subcommand_from prune" -a "(__git_subtrees_paths)" -d 'subtree path'
complete -c git-subtrees -n "__fish_seen_subcommand_from prune" -s n -l dry-run -d 'show stale refs without pruning'
complete -c git-subtrees -n "__fish_seen_subcommand_from prune" -s h -l help -d 'show usage'

complete -c git-subtrees -n "__fish_seen_subcommand_from init" -s h -l help -d 'show usage'
complete -c git-subtrees -n "__fish_seen_subcommand_from init; and test (count (commandline -opc)) -le 2" -a "(__fish_complete_directories)"
