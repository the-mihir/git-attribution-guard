# shellcheck shell=sh
# Commit message filtering: modes, allowlist, precedence, idempotency.

test_strip_ai_default() {
  install_guard; new_repo r
  commit "$AI_MSG"
  m=$(last_msg)
  assert_not_contains "$m" "anthropic.com"
  assert_not_contains "$m" "Copilot"
  assert_not_contains "$m" "Generated with"
  assert_contains "$m" "Co-authored-by: Pritom <pritom@example.com>" "human co-author kept"
  assert_contains "$m" "Signed-off-by: Test User <test@example.com>" "human sign-off kept"
  assert_contains "$m" "Body."
}

test_filter_is_idempotent() {
  install_guard; new_repo r
  printf '%s\n' "$AI_MSG" > msg
  attribution hook commit-msg msg 2>/dev/null
  cp msg once
  attribution hook commit-msg msg 2>/dev/null
  assert_ok cmp -s once msg
  printf 'Plain subject\n\n\n\nbody\n' > plain
  cp plain plain.orig
  attribution hook commit-msg plain 2>/dev/null
  assert_ok cmp -s plain plain.orig   # untouched when nothing to remove
}

test_trailing_blank_lines_cleaned() {
  install_guard; new_repo r
  printf 'Subject\n\nCo-authored-by: Claude <noreply@anthropic.com>\n\n' > msg
  attribution hook commit-msg msg 2>/dev/null
  assert_eq "Subject" "$(cat msg)"
  assert_eq 1 "$(wc -l < msg | tr -d ' ')"
}

test_other_ai_tools_and_bots() {
  install_guard; new_repo r
  commit 'x

Co-authored-by: Cursor Agent <cursoragent@cursor.com>
Co-authored-by: aider (gpt-5) <noreply@aider.chat>
Co-authored-by: devin-ai-integration[bot] <158243242+devin-ai-integration[bot]@users.noreply.github.com>
Co-authored-by: gemini-code-assist[bot] <gemini@example.com>
Co-authored-by: Codex <codex@openai.com>
Co-authored-by: Raider Smith <raider@example.com>
Assisted-by: Windsurf <x@codeium.com>
Signed-off-by: Claude <noreply@anthropic.com>'
  m=$(last_msg)
  assert_eq "x

Co-authored-by: Raider Smith <raider@example.com>" "$m" "only the human (word-boundary match) is kept"
}

test_allowlist_mode() {
  install_guard; new_repo r
  attribution mode allowlist >/dev/null 2>&1
  attribution allow add PRITOM@example.com >/dev/null 2>&1
  commit 'x

Co-authored-by: Pritom <pritom@example.com>
Co-authored-by: Someone Else <else@example.com>
Co-authored-by: Claude <noreply@anthropic.com>
Signed-off-by: Someone Else <else@example.com>'
  m=$(last_msg)
  assert_contains "$m" "pritom@example.com" "allowed email kept (case-insensitive)"
  assert_not_contains "$m" "Co-authored-by: Someone Else"
  assert_not_contains "$m" "anthropic"
  assert_contains "$m" "Signed-off-by: Someone Else" "human Signed-off-by never touched"
}

test_allowlist_domain_and_ai_override() {
  install_guard; new_repo r
  attribution allow add @corp.example >/dev/null 2>&1
  attribution allow add claude@family.example >/dev/null 2>&1
  attribution mode allowlist >/dev/null 2>&1
  commit 'x

Co-authored-by: A <a@corp.example>
Co-authored-by: B <b@evilcorp.example>
Co-authored-by: Claude Dupont <claude@family.example>'
  m=$(last_msg)
  assert_contains "$m" "a@corp.example"
  assert_not_contains "$m" "evilcorp"
  assert_contains "$m" "claude@family.example" "allowlist overrides AI pattern"
}

test_strip_all_mode() {
  install_guard; new_repo r
  attribution mode strip-all >/dev/null 2>&1
  attribution allow add pritom@example.com >/dev/null 2>&1
  commit "$AI_MSG"
  m=$(last_msg)
  assert_not_contains "$m" "Co-authored-by"
  assert_contains "$m" "Signed-off-by: Test User"
}

test_off_and_disabled() {
  install_guard; new_repo r
  attribution off >/dev/null 2>&1
  commit "$AI_MSG"
  assert_contains "$(last_msg)" "anthropic.com" "enabled=false leaves message alone"
  attribution on >/dev/null 2>&1
  attribution mode off >/dev/null 2>&1
  commit "$AI_MSG"
  assert_contains "$(last_msg)" "anthropic.com" "mode=off leaves message alone"
}

test_local_overrides_global() {
  install_guard
  attribution mode strip-all >/dev/null 2>&1
  new_repo a
  commit "$AI_MSG"
  assert_not_contains "$(last_msg)" "Pritom" "global strip-all applies"
  new_repo b
  attribution mode strip-ai --local >/dev/null 2>&1
  commit "$AI_MSG"
  assert_contains "$(last_msg)" "Pritom" "local strip-ai wins"
  attribution off --local >/dev/null 2>&1
  commit "$AI_MSG"
  assert_contains "$(last_msg)" "anthropic.com" "local off wins"
  cd "$SANDBOX/a" && commit "$AI_MSG"
  assert_not_contains "$(last_msg)" "anthropic.com" "other repo unaffected"
  s=$(cd "$SANDBOX/b" && attribution status 2>&1)
  assert_contains "$s" "local"
}

test_extra_patterns() {
  install_guard; new_repo r
  git config --global --add attribution.extraPatterns '\bacme-agent\b'
  commit 'x

Co-authored-by: ACME-Agent <agent@acme.example>
Co-authored-by: Human <h@acme.example>'
  m=$(last_msg)
  assert_not_contains "$m" "ACME-Agent"
  assert_contains "$m" "Human"
}

test_verbose_commit_scissors_untouched() {
  install_guard; new_repo r
  printf 'Subject\n\nCo-authored-by: Claude <noreply@anthropic.com>\n# ------------------------ >8 ------------------------\n+Co-authored-by: Claude <noreply@anthropic.com>\n' > msg
  attribution hook commit-msg msg 2>/dev/null
  assert_eq 'Subject

# ------------------------ >8 ------------------------
+Co-authored-by: Claude <noreply@anthropic.com>' "$(cat msg)"
}
