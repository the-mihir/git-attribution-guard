# shellcheck shell=sh
# Claude Code settings merge, agent instructions, check, rewrite, uninstall.

json_get() {  # json_get <file> <python-expr on d>
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(eval(sys.argv[2])))' "$1" "$2"
}

settings_merge_with() {
  command -v "$1" >/dev/null 2>&1 || { echo "$1 not installed"; return 77; }
  mkdir -p "$HOME/.claude"
  printf '{\n  "model": "opus",\n  "permissions": {"allow": ["Bash(ls)"]},\n  "attribution": {"other": 1}\n}\n' > "$HOME/.claude/settings.json"
  cp "$HOME/.claude/settings.json" "$SANDBOX/orig.json"
  GAG_JSON_TOOL=$1 install_guard
  f="$HOME/.claude/settings.json"
  assert_eq '"opus"' "$(json_get "$f" 'd["model"]')" "$1 keeps keys"
  assert_eq '["Bash(ls)"]' "$(json_get "$f" 'd["permissions"]["allow"]')"
  assert_eq '{"other": 1, "commit": "", "pr": ""}' "$(json_get "$f" 'd["attribution"]')"
  assert_eq 'false' "$(json_get "$f" 'd["includeCoAuthoredBy"]')"
  assert_eq 1 "$(find "$HOME/.claude" -maxdepth 1 -name 'settings.json.bak-*' | wc -l | tr -d ' ')" "one backup"
  GAG_JSON_TOOL=$1 attribution install >/dev/null 2>&1
  assert_eq 1 "$(find "$HOME/.claude" -maxdepth 1 -name 'settings.json.bak-*' | wc -l | tr -d ' ')" "idempotent: no new backup"
  GAG_JSON_TOOL=$1 attribution uninstall >/dev/null 2>&1
  assert_eq "$(json_get "$SANDBOX/orig.json" 'd')" "$(json_get "$f" 'd')" "$1 revert restores original"
}

test_claude_settings_jq() { settings_merge_with jq; }
test_claude_settings_node() { settings_merge_with node; }
test_claude_settings_python() { settings_merge_with python3; }

test_claude_settings_created_and_invalid_json_untouched() {
  install_guard
  assert_eq 'false' "$(json_get "$HOME/.claude/settings.json" 'd["includeCoAuthoredBy"]')" "created when missing"
  sh "$ROOT/install.sh" --uninstall >/dev/null 2>&1
  printf '{ not json' > "$HOME/.claude/settings.json"
  assert_fails sh "$ROOT/install.sh" --no-skill
  assert_eq '{ not json' "$(cat "$HOME/.claude/settings.json")" "invalid file untouched"
}

test_local_claude_settings_and_agent_instructions() {
  install_guard; new_repo r
  printf '# Project\n' > CLAUDE.md
  attribution install --local --agent-instructions >/dev/null 2>&1
  assert_eq 'false' "$(json_get .claude/settings.json 'd["includeCoAuthoredBy"]')"
  assert_file_contains CLAUDE.md "Never add \`Co-authored-by:\`"
  assert_fails test -f AGENTS.md
  attribution install --local --agent-instructions >/dev/null 2>&1
  assert_eq 1 "$(grep -c 'git-attribution-guard >>>' CLAUDE.md)" "idempotent"
  attribution uninstall --local >/dev/null 2>&1
  assert_eq '# Project' "$(cat CLAUDE.md)"
}

test_check_reports_and_exit_codes() {
  install_guard; new_repo r
  commit "clean"
  assert_ok attribution check
  commit "$AI_MSG" --no-verify
  out=$(attribution check 2>&1); rc=$?
  assert_eq 1 "$rc" "check exits 1 on findings"
  assert_contains "$out" "AI co-author"
  assert_contains "$out" "Generated with"
  assert_ok attribution check HEAD~1
}

need_filter_repo() {
  git filter-repo --version >/dev/null 2>&1 || { echo "git-filter-repo not installed"; return 77; }
}

test_rewrite_dry_run_changes_nothing() {
  install_guard; new_repo r
  commit "one"; commit "$AI_MSG" --no-verify; commit "three"
  before=$(git rev-parse HEAD)
  out=$(attribution rewrite --dry-run 2>&1)
  assert_contains "$out" "Co-authored-by: Claude Opus 5.5"
  assert_contains "$out" "dry run"
  assert_eq "$before" "$(git rev-parse HEAD)"
  assert_eq "" "$(git for-each-ref refs/attribution-backup)"
}

test_rewrite_removes_ai_and_keeps_origin() {
  need_filter_repo || return 77
  install_guard; new_repo r
  git remote add origin https://example.invalid/me/repo.git
  commit "one"; commit "$AI_MSG" --no-verify; commit "three"
  echo nope | attribution rewrite >/dev/null 2>&1
  assert_contains "$(git log --format=%B)" "anthropic" "no rewrite without typed confirmation"
  out=$(echo rewrite | attribution rewrite 2>&1)
  assert_contains "$out" "git push --force-with-lease --all origin"
  assert_contains "$out" "contributors graph"
  log=$(git log --format=%B)
  assert_not_contains "$log" "anthropic"
  assert_not_contains "$log" "Generated with"
  assert_contains "$log" "Co-authored-by: Pritom <pritom@example.com>"
  assert_eq 3 "$(git rev-list --count HEAD)"
  assert_eq "https://example.invalid/me/repo.git" "$(git remote get-url origin)"
  assert_ok attribution check
  assert_contains "$(git for-each-ref --format='%(refname)' refs/attribution-backup)" "/heads/main"
}

test_rewrite_mailmap_and_dirty_tree() {
  need_filter_repo || return 77
  install_guard; new_repo r
  commit "one"
  commit "two" --author="Old Me <old@example.com>"
  printf 'Test User <test@example.com> <old@example.com>\n' > "$SANDBOX/mailmap"
  out=$(attribution rewrite --mailmap "$SANDBOX/mailmap" --dry-run 2>&1)
  assert_contains "$out" "Old Me <old@example.com> -> Test User <test@example.com>"
  echo dirty > f && git add f
  assert_fails sh -c 'echo rewrite | attribution rewrite --mailmap "$0"' "$SANDBOX/mailmap"
  git commit -q -m "add f"
  echo rewrite | attribution rewrite --mailmap "$SANDBOX/mailmap" >/dev/null 2>&1
  assert_not_contains "$(git log --format='%an <%ae>')" "old@example.com"
}

test_install_twice_and_uninstall_restores() {
  mkdir -p "$HOME/.claude"
  printf '{"theme": "dark"}\n' > "$HOME/.claude/settings.json"
  cp "$HOME/.gitconfig" "$SANDBOX/gitconfig.orig"
  sh "$ROOT/install.sh" --agent-instructions >/dev/null 2>&1 || fail "install"
  cp "$HOME/.gitconfig" "$SANDBOX/gitconfig.1"
  sum1=$(cd "$HOME" && find .local .claude -type f ! -name '*.bak-*' | sort | xargs cksum)
  sh "$ROOT/install.sh" --agent-instructions >/dev/null 2>&1 || fail "install twice"
  sum2=$(cd "$HOME" && find .local .claude -type f ! -name '*.bak-*' | sort | xargs cksum)
  assert_eq "$sum1" "$sum2" "second install changes nothing"
  assert_ok cmp -s "$SANDBOX/gitconfig.1" "$HOME/.gitconfig"
  assert_ok test -f "$HOME/.claude/skills/git-attribution-guard/SKILL.md"
  assert_file_contains "$HOME/.claude/CLAUDE.md" "git-attribution-guard"

  sh "$ROOT/install.sh" --uninstall >/dev/null 2>&1 || fail "uninstall"
  assert_ok cmp -s "$SANDBOX/gitconfig.orig" "$HOME/.gitconfig"
  assert_eq '{"theme": "dark"}' "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))))' "$HOME/.claude/settings.json")"
  assert_fails test -e "$HOME/.claude/CLAUDE.md"
  assert_fails test -e "$HOME/.claude/skills/git-attribution-guard"
  assert_fails test -e "$HOME/.local/bin/attribution"
  assert_fails test -e "$HOME/.local/share/git-attribution-guard"
}

test_doctor_and_help() {
  install_guard; new_repo r
  assert_ok attribution doctor
  assert_contains "$(attribution rewrite --help)" "--dry-run"
  assert_contains "$(attribution version)" "$(cat "$ROOT/VERSION")"
  git config --global --add attribution.extraPatterns '(unclosed'
  assert_fails attribution doctor
}
