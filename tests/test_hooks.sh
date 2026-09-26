# shellcheck shell=sh
# Author enforcement, pre-push blocking, hook chaining, Husky integration.

test_author_enforcement() {
  install_guard; new_repo r
  attribution author set "Test User" test@example.com >/dev/null 2>&1
  assert_ok commit "ok"
  git config user.email other@example.com
  assert_fails commit "blocked"
  out=$(git commit --allow-empty -m blocked 2>&1)
  assert_contains "$out" "does not match"
  assert_contains "$out" "git config user.email"
  assert_ok commit "one-off" --author="Test User <test@example.com>"
  attribution author clear >/dev/null 2>&1
  assert_ok commit "cleared"
}

test_ai_author_blocked() {
  install_guard; new_repo r
  assert_fails commit "bot" --author="Claude <noreply@anthropic.com>"
  attribution allow add noreply@anthropic.com >/dev/null 2>&1
  assert_ok commit "allowed bot" --author="Claude <noreply@anthropic.com>"
}

setup_remote() {
  git init -q --bare "$SANDBOX/remote.git"
  git remote add origin "$SANDBOX/remote.git"
}

test_prepush_blocks_no_verify_commits() {
  install_guard; new_repo r; setup_remote
  commit "clean"
  assert_ok git push -q origin main
  commit "$AI_MSG" --no-verify
  out=$(git push origin main 2>&1); rc=$?
  assert_eq 1 "$([ $rc -ne 0 ] && echo 1)" "push must fail"
  assert_contains "$out" "push blocked"
  assert_contains "$out" "noreply@anthropic.com"
  assert_contains "$out" "attribution rewrite"
  git commit -q --amend --allow-empty -m "fixed"
  assert_ok git push -q origin main
}

test_prepush_new_branch_and_delete() {
  install_guard; new_repo r; setup_remote
  commit "base"; git push -q origin main
  git checkout -q -b feature
  commit "clean feature"
  assert_ok git push -q origin feature
  git checkout -q -b bad
  commit "x

Co-authored-by: Copilot <175728472+Copilot@users.noreply.github.com>" --no-verify
  assert_fails git push -q origin bad
  assert_ok git push -q origin --delete feature
  git config --global attribution.blockPush false
  assert_ok git push -q origin bad
}

test_prepush_ai_author_via_no_verify() {
  install_guard; new_repo r; setup_remote
  commit "base"; git push -q origin main
  commit "bot" --no-verify --author="Devin <devin-ai-integration[bot]@users.noreply.github.com>"
  out=$(git push origin main 2>&1)
  assert_contains "$out" "AI author"
}

test_chains_existing_repo_hooks() {
  install_guard; new_repo r; setup_remote
  cat > .git/hooks/commit-msg <<'H'
#!/bin/sh
printf '\nChange-Id: I123\n' >> "$1"
H
  cat > .git/hooks/pre-push <<'H'
#!/bin/sh
cat > "$HOME/prepush.stdin"
echo "$1 $2" > "$HOME/prepush.args"
H
  cat > .git/hooks/pre-commit <<'H'
#!/bin/sh
[ ! -f "$HOME/block" ] || { echo "repo pre-commit says no" >&2; exit 3; }
H
  chmod +x .git/hooks/commit-msg .git/hooks/pre-push .git/hooks/pre-commit
  commit "$AI_MSG"
  m=$(last_msg)
  assert_contains "$m" "Change-Id: I123" "repo commit-msg hook ran"
  assert_not_contains "$m" "anthropic" "guard still filtered"
  touch "$HOME/block"
  out=$(git commit --allow-empty -m x 2>&1)
  assert_contains "$out" "repo pre-commit says no" "repo pre-commit ran and blocked"
  rm "$HOME/block"
  git push -q origin main 2>/dev/null
  assert_file_contains "$HOME/prepush.stdin" "refs/heads/main"
  assert_file_contains "$HOME/prepush.args" "origin "
  assert_file_contains "$HOME/prepush.args" "remote.git"
}

test_passthrough_hooks_keep_working() {
  install_guard; new_repo r
  cat > .git/hooks/post-commit <<'H'
#!/bin/sh
echo ran > "$HOME/post-commit.ran"
H
  chmod +x .git/hooks/post-commit
  commit "x"
  assert_ok test -f "$HOME/post-commit.ran"
}

test_previous_global_hookspath_is_chained_and_restored() {
  mkdir -p "$SANDBOX/myhooks"
  printf '#!/bin/sh\necho global > "$HOME/global-hook.ran"\n' > "$SANDBOX/myhooks/pre-commit"
  chmod +x "$SANDBOX/myhooks/pre-commit"
  git config --global core.hooksPath "$SANDBOX/myhooks"
  install_guard
  assert_contains "$(cat "$SANDBOX/install.log")" "remembered"
  new_repo r
  commit "x"
  assert_ok test -f "$HOME/global-hook.ran"
  sh "$ROOT/install.sh" --uninstall >/dev/null 2>&1
  restored=$(git config --global core.hooksPath)
  assert_eq "$SANDBOX/myhooks" "$(cd "$restored" && pwd -P)" "previous hooksPath restored"
  assert_fails git config --global attribution.previousHooksPath
}

make_husky() {
  mkdir -p .husky/_
  for h in pre-commit commit-msg pre-push; do
    printf '#!/usr/bin/env sh\ns="$(dirname "$(dirname "$0")")/%s"\n[ -f "$s" ] || exit 0\nsh -e "$s" "$@"\n' "$h" > ".husky/_/$h"
    chmod +x ".husky/_/$h"
  done
  printf 'echo husky-pre-commit >> "$HOME/husky.log"\n' > .husky/pre-commit
  git config core.hooksPath .husky/_
}

test_husky_local_hookspath_integration() {
  install_guard; new_repo r; setup_remote
  make_husky
  cp .husky/pre-commit "$SANDBOX/pre-commit.orig"
  s=$(attribution status 2>&1)
  assert_contains "$s" "NOT active"
  assert_fails attribution doctor
  commit "$AI_MSG"
  assert_contains "$(last_msg)" "anthropic" "guard silently bypassed before integration"

  attribution install --local >/dev/null 2>&1
  assert_contains "$(attribution status 2>&1)" "integrated"
  assert_eq ".husky/_" "$(git config --local core.hooksPath)" "husky hooksPath untouched"
  commit "$AI_MSG"
  assert_not_contains "$(last_msg)" "anthropic"
  assert_file_contains "$HOME/husky.log" "husky-pre-commit"
  commit "bad" --no-verify --author="Claude <noreply@anthropic.com>"
  assert_fails git push -q origin main

  attribution install --local >/dev/null 2>&1
  assert_eq 1 "$(grep -c 'git-attribution-guard >>>' .husky/pre-commit)" "idempotent"

  attribution uninstall --local >/dev/null 2>&1
  assert_ok cmp -s "$SANDBOX/pre-commit.orig" .husky/pre-commit
  assert_fails test -f .husky/commit-msg
  assert_fails test -f .husky/pre-push
}

test_local_install_without_global() {
  sh "$ROOT/install.sh" --no-skill --no-configure >/dev/null 2>&1
  new_repo r
  assert_fails git config --global core.hooksPath
  attribution install --local >/dev/null 2>&1
  commit "$AI_MSG"
  assert_not_contains "$(last_msg)" "anthropic"
  new_repo other
  commit "$AI_MSG"
  assert_contains "$(last_msg)" "anthropic" "other repos untouched"
  cd "$SANDBOX/r" && attribution uninstall --local >/dev/null 2>&1
  assert_fails git config --local core.hooksPath
}
