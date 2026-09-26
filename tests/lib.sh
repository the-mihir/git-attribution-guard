# shellcheck shell=sh disable=SC2034
# Minimal test helpers (plain POSIX sh; bats-core not required).

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
FAILS=0

fail() { printf '    FAIL: %s\n' "$*" >&2; FAILS=$((FAILS + 1)); }

assert_eq() {  # expected actual [message]
  [ "$1" = "$2" ] || fail "${3:-values differ}: expected [$1] got [$2]"
}
assert_contains() {  # haystack needle [message]
  case $1 in *"$2"*) ;; *) fail "${3:-missing text}: [$2] not in [$1]" ;; esac
}
assert_not_contains() {
  case $1 in *"$2"*) fail "${3:-unexpected text}: [$2] found in [$1]" ;; esac
}
assert_ok() { "$@" >/dev/null 2>&1 || fail "command failed: $*"; }
assert_fails() { if "$@" >/dev/null 2>&1; then fail "command should fail: $*"; fi; }
assert_file_contains() { grep -qF -- "$2" "$1" 2>/dev/null || fail "file $1 lacks [$2]"; }

# Fresh HOME, git config and install for every test.
setup() {
  SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/gag-test.XXXXXX")
  SANDBOX=$(CDPATH='' cd -- "$SANDBOX" && pwd -P)
  export HOME="$SANDBOX/home"
  mkdir -p "$HOME"
  unset XDG_DATA_HOME XDG_STATE_HOME XDG_CONFIG_HOME CLAUDE_CONFIG_DIR GIT_CONFIG_GLOBAL GAG_JSON_TOOL NO_COLOR
  export GIT_CONFIG_NOSYSTEM=1 NO_COLOR=1
  export PATH="$HOME/.local/bin:$BASE_PATH"
  git config --global user.name "Test User"
  git config --global user.email test@example.com
  git config --global init.defaultBranch main
  git config --global commit.gpgsign false
  git config --global advice.detachedHead false
  cd "$SANDBOX" || exit 1
}

teardown() {
  cd / && rm -rf "$SANDBOX"
}

install_guard() {  # extra install.sh args
  sh "$ROOT/install.sh" --no-skill "$@" >"$SANDBOX/install.log" 2>&1 || {
    cat "$SANDBOX/install.log" >&2; fail "install.sh failed"; return 1; }
}

new_repo() {
  git init -q "$SANDBOX/$1" && cd "$SANDBOX/$1" || exit 1
}

commit() {  # commit <message> [git commit args]
  _m=$1; shift
  git commit -q --allow-empty -m "$_m" "$@"
}

last_msg() { git log -1 --format=%B; }

AI_MSG='Add feature

Body.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-authored-by: Claude Opus 5.5 <noreply@anthropic.com>
Co-authored-by: Pritom <pritom@example.com>
Co-authored-by: Copilot <175728472+Copilot@users.noreply.github.com>
Signed-off-by: Test User <test@example.com>'
