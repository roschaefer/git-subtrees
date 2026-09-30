# Runs real pushes through the installed pre-push hook, so git decides what
# the hook sees -- the same as for a user.

setup() {
  load 'helpers/fixtures'
  load 'scenarios/push-ahead/setup'
  load 'scenarios/diverged-unrelated-history/setup'
  # A global core.hooksPath would move the hook out of the monorepo.
  hermetic_git_config
  entrypoint="$BATS_TEST_DIRNAME/../git-subtrees"
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

upstream_ref() {
  git -C "$upstream" rev-parse --verify --quiet "refs/heads/$1" || echo none
}

@test "install-hook: a forced push of a monorepo branch to its subtree remote is refused" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  "$entrypoint" install-hook
  local before
  before="$(upstream_ref main)"

  run git push --force vendor/a main:main
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to push refs/heads/main to 'vendor/a'"* ]]
  [[ "$output" == *"has a folder 'vendor/a/', so it's the monorepo"* ]]
  [ "$(upstream_ref main)" = "$before" ]
}

@test "install-hook: a monorepo branch the remote doesn't have yet is refused too" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  "$entrypoint" install-hook

  run git push vendor/a HEAD:refs/heads/leak
  [ "$status" -ne 0 ]
  [ "$(upstream_ref leak)" = none ]
}

@test "install-hook: a monorepo commit pushed by its SHA is refused" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  "$entrypoint" install-hook

  run git push vendor/a "$(git rev-parse HEAD):refs/heads/leak"
  [ "$status" -ne 0 ]
  [ "$(upstream_ref leak)" = none ]
}

@test "install-hook: 'git subtrees push' still pushes the subtree" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  "$entrypoint" install-hook

  run "$entrypoint" push
  [ "$status" -eq 0 ]
  [ "$(upstream_ref main)" = "$(git subtree split -q --prefix=vendor/a HEAD)" ]
}

@test "install-hook: the printed fix for unrelated history, a split branch force-pushed, still works" {
  scenario_diverged_unrelated_history "$monorepo" "$upstream"
  cd "$monorepo"
  "$entrypoint" install-hook

  git subtree split -q --prefix=vendor/a -b tmp-split-a
  run git push --force vendor/a tmp-split-a:main
  [ "$status" -eq 0 ]
  [ "$(upstream_ref main)" = "$(git rev-parse tmp-split-a)" ]
}

@test "install-hook: pushing the monorepo to a remote that isn't a subtree is allowed" {
  scenario_push_ahead "$monorepo" "$upstream"
  local origin="$BATS_TEST_TMPDIR/origin.git"
  make_bare_repo "$origin"
  cd "$monorepo"
  git remote add origin "$origin"
  "$entrypoint" install-hook

  run git push origin main
  [ "$status" -eq 0 ]
}

@test "install-hook: pushing the monorepo to a URL rather than a remote is allowed" {
  scenario_push_ahead "$monorepo" "$upstream"
  local mirror="$BATS_TEST_TMPDIR/mirror.git"
  make_bare_repo "$mirror"
  cd "$monorepo"
  "$entrypoint" install-hook

  run git push "$mirror" main
  [ "$status" -eq 0 ]
}

@test "install-hook: deleting a branch on a subtree remote is allowed" {
  scenario_push_ahead "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "feature work" feature
  cd "$monorepo"
  "$entrypoint" install-hook

  run git push vendor/a --delete feature
  [ "$status" -eq 0 ]
  [ "$(upstream_ref feature)" = none ]
}

@test "install-hook: protects pushes from a linked worktree too" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  "$entrypoint" install-hook
  git worktree add -q "$BATS_TEST_TMPDIR/worktree" -b other
  cd "$BATS_TEST_TMPDIR/worktree"

  run git push vendor/a other
  [ "$status" -ne 0 ]
  [ "$(upstream_ref other)" = none ]
}

@test "install-hook: a subtree with a folder named like its own path is a false alarm, pushed with --no-verify" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir -p vendor/a/vendor/a
  echo nested >vendor/a/vendor/a/file.txt
  git add vendor/a
  git commit -q -m "a folder named like the subtree"
  "$entrypoint" install-hook
  local split
  split="$(git subtree split -q --prefix=vendor/a HEAD)"

  run git push vendor/a "$split:refs/heads/main"
  [ "$status" -ne 0 ]
  [[ "$output" == *"push with --no-verify"* ]]

  run git push --no-verify vendor/a "$split:refs/heads/main"
  [ "$status" -eq 0 ]
  [ "$(upstream_ref main)" = "$split" ]
}

@test "install-hook: lists the subtree remotes it protects" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir -p ghost-folder
  git remote add ghost "$BATS_TEST_TMPDIR/ghost.git"

  run "$entrypoint" install-hook
  [ "$status" -eq 0 ]
  [ "$output" = "ok   installed pre-push hook: .git/hooks/pre-push
ok   vendor/a: protected from a plain 'git push' of the monorepo
ok   subtrees you add later are protected too" ]
}

@test "install-hook: re-running reports the hook as installed" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  "$entrypoint" install-hook

  run "$entrypoint" install-hook
  [ "$status" -eq 0 ]
  [[ "$output" == "ok   pre-push hook already installed: .git/hooks/pre-push"* ]]
}

@test "install-hook: replaces an unedited hook of an earlier git-subtrees version" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  local body="$BATS_TEST_TMPDIR/body"
  printf 'echo "an earlier check"\n' >"$body"
  {
    echo '#!/bin/sh'
    echo "# git-subtrees pre-push hook $(cksum <"$body" | cut -d' ' -f1)"
    cat "$body"
  } >.git/hooks/pre-push
  chmod +x .git/hooks/pre-push

  run "$entrypoint" install-hook
  [ "$status" -eq 0 ]
  [[ "$output" == "ok   installed pre-push hook: .git/hooks/pre-push"* ]]
  [ "$(cat .git/hooks/pre-push)" = "$("$entrypoint" install-hook --print)" ]
}

@test "install-hook: leaves an edited hook of an earlier git-subtrees version alone" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  "$entrypoint" install-hook
  echo "# my own addition" >>.git/hooks/pre-push
  sed -i 's/^# git-subtrees pre-push hook .*/# git-subtrees pre-push hook 1/' .git/hooks/pre-push
  local before
  before="$(cat .git/hooks/pre-push)"

  run "$entrypoint" install-hook
  [ "$status" -eq 1 ]
  [ "$(cat .git/hooks/pre-push)" = "$before" ]
}

@test "install-hook: makes a hook that isn't executable, which git ignores, executable" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  "$entrypoint" install-hook
  chmod -x .git/hooks/pre-push

  run "$entrypoint" install-hook
  [ "$status" -eq 0 ]
  [ -x .git/hooks/pre-push ]
}

@test "install-hook: leaves a pre-push hook it didn't write alone and fails" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  printf '#!/bin/sh\necho mine\n' >.git/hooks/pre-push

  run "$entrypoint" install-hook
  [ "$status" -eq 1 ]
  [[ "$output" == *".git/hooks/pre-push already exists and isn't git-subtrees' own"* ]]
  [ "$(cat .git/hooks/pre-push)" = $'#!/bin/sh\necho mine' ]
}

@test "install-hook: a hook combined with the printed one refuses the monorepo and counts as installed" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local printed="$BATS_TEST_TMPDIR/printed"
  "$entrypoint" install-hook --print >"$printed"
  {
    echo '#!/bin/sh'
    echo 'input=$(cat)'
    echo 'echo "my own check" >&2'
    printf '%s\n' "$(sed -n 2p "$printed")"
    echo "printf '%s\n' \"\$input\" | sh $(printf '%q' "$printed") \"\$@\""
  } >.git/hooks/pre-push
  chmod +x .git/hooks/pre-push

  run git push vendor/a main:leak
  [ "$status" -ne 0 ]
  [[ "$output" == *"my own check"* ]]
  [[ "$output" == *"refusing to push refs/heads/main to 'vendor/a'"* ]]

  run "$entrypoint" status
  [[ "$output" != *"install-hook"* ]]
  run "$entrypoint" install-hook
  [ "$status" -eq 0 ]
  [[ "$output" == "ok   pre-push hook already installed"* ]]
}

@test "install-hook: installs into core.hooksPath if it's set" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git config core.hooksPath .githooks

  run "$entrypoint" install-hook
  [ "$status" -eq 0 ]
  [ -x .githooks/pre-push ]
}

@test "install-hook: works from a subdirectory" {
  init_monorepo "$monorepo"
  mkdir "$monorepo/sub"
  cd "$monorepo/sub"

  run "$entrypoint" install-hook
  [ "$status" -eq 0 ]
  [ -x "$monorepo/.git/hooks/pre-push" ]
}

@test "init: doesn't install the hook, but says how to" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"

  run "$entrypoint" init vendor/a "$upstream"
  [ "$status" -eq 0 ]
  [[ "$output" == *"run 'git subtrees install-hook' to refuse that" ]]
  [ ! -e .git/hooks/pre-push ]
}

@test "init: says nothing about the hook once it's installed" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  "$entrypoint" install-hook

  run "$entrypoint" init vendor/a "$upstream"
  [ "$status" -eq 0 ]
  [[ "$output" != *"install-hook"* ]]
}

@test "status: says how to install the hook while it's missing" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"

  run "$entrypoint" status
  [[ "$output" == *"??   a plain 'git push' can send the monorepo to a subtree remote -- run 'git subtrees install-hook' to refuse that" ]]

  "$entrypoint" install-hook
  run "$entrypoint" status
  [[ "$output" != *"install-hook"* ]]
}

@test "status: says to update a hook of an earlier git-subtrees version" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  "$entrypoint" install-hook
  chmod -x .git/hooks/pre-push

  run "$entrypoint" status
  [[ "$output" == *".git/hooks/pre-push is from another git-subtrees version -- run 'git subtrees install-hook' to update it" ]]
}

@test "status: points out a pre-push hook of your own that doesn't protect the subtrees" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  printf '#!/bin/sh\necho mine\n' >.git/hooks/pre-push
  chmod +x .git/hooks/pre-push

  run "$entrypoint" status
  [[ "$output" == *".git/hooks/pre-push doesn't refuse a plain 'git push' of the monorepo to a subtree remote -- see 'git subtrees install-hook -h'" ]]
}

@test "status: says nothing about the hook without subtrees" {
  init_monorepo "$monorepo"
  cd "$monorepo"

  run "$entrypoint" status
  [[ "$output" != *"install-hook"* ]]
}
