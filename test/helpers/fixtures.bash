# Low-level git-plumbing helpers shared by test/scenarios/*/setup.bash.
# Named scenarios compose these into the specific history shapes bats
# tests exercise -- see each scenario folder's README.md.

make_bare_repo() {
  git init -q --bare --initial-branch=main "$1"
}

# Clones $1, appends line $2 to file.txt (creating it if needed), commits
# with message $2, and pushes to branch $3 (default: main).
seed_bare_repo() {
  local repo="$1" msg="$2" branch="${3:-main}" tmp
  tmp="$(mktemp -d)"
  git clone -q "$repo" "$tmp" 2>/dev/null
  (
    cd "$tmp"
    git config user.name "Test"
    git config user.email "test@example.com"
    if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
      git fetch -q origin "$branch"
      git checkout -q -B "$branch" "origin/$branch"
    else
      git checkout -q -B "$branch"
    fi
    echo "$msg" >>file.txt
    git add file.txt
    git commit -q -m "$msg"
    git push -q origin "HEAD:$branch"
  )
  rm -rf "$tmp"
}

# Initializes a monorepo working tree at $1 with local git identity (CI
# runners have no global one) and one initial commit. Does not cd --
# callers use their own cwd or a subshell.
init_monorepo() {
  git init -q -b main "$1"
  (
    cd "$1"
    git config user.name "Test"
    git config user.email "test@example.com"
    git commit -q --allow-empty -m "initial commit"
  )
}

# Adds bare repo $2 to $3 inside monorepo $1 via raw git plumbing --
# deliberately NOT via cmd_init, so other commands' tests don't depend on
# init's own correctness or implementation order.
add_subtree() {
  local monorepo="$1" remote_url="$2" path="$3" branch="${4:-main}"
  (
    cd "$monorepo"
    git remote add "$path" "$remote_url"
    git fetch -q "$path"
    git subtree add -q --prefix="$path" "$path" "$branch" --squash
  )
}

# Ignores the developer's own git config (e.g. a global init.defaultBranch),
# so tests about how the base branch is resolved behave the same everywhere.
# Bats runs each test in its own subshell, so this never leaks.
hermetic_git_config() {
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
}

# Sources every lib/*.sh file so tests can call functions directly, mirroring
# the order the real entrypoint uses.
load_lib() {
  local lib_dir="$BATS_TEST_DIRNAME/../lib"
  # shellcheck disable=SC1091
  source "$lib_dir/common.sh"
  # shellcheck disable=SC1091
  source "$lib_dir/init.sh"
  # shellcheck disable=SC1091
  source "$lib_dir/fetch.sh"
  # shellcheck disable=SC1091
  source "$lib_dir/pull.sh"
  # shellcheck disable=SC1091
  source "$lib_dir/prune.sh"
  # shellcheck disable=SC1091
  source "$lib_dir/push.sh"
  # shellcheck disable=SC1091
  source "$lib_dir/diff.sh"
  # shellcheck disable=SC1091
  source "$lib_dir/status.sh"
}
