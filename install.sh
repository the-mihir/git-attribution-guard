#!/bin/sh
# Install git-attribution-guard: the `attribution` CLI, its git hooks and the
# Claude Code skill. Works offline from a checkout or a release archive.
# SPDX-License-Identifier: MIT
set -eu

NAME=git-attribution-guard
SRC=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}/$NAME"
BIN_DIR="$HOME/.local/bin"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SCOPE=global
SKILL=1
CONFIGURE=1
AGENT=
UNINSTALL=0
MARKER=".$NAME-install"

usage() {
  cat <<EOF
Usage: ./install.sh [options]

  --global               install for your user (default)
  --local                also enable the guard for the current repository only,
                         and put the skill in ./.claude/skills/
  --prefix DIR           where the CLI and hooks live   (default: $PREFIX)
  --bin-dir DIR          where the \`attribution\` command goes (default: $BIN_DIR)
  --no-skill             do not install the Claude Code skill
  --no-configure         only copy files; do not run \`attribution install\`
  --agent-instructions   add a "no AI co-authors" note to CLAUDE.md / AGENTS.md
  --uninstall            remove what this script installed
  -h, --help             show this help

Nothing is downloaded. Running it twice changes nothing.
EOF
}

say()  { printf '%s\n' "$*" >&2; }
die()  { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case $1 in
    --global) SCOPE=global ;;
    --local) SCOPE=local ;;
    --prefix) [ $# -ge 2 ] || die "--prefix needs a directory"; PREFIX=$2; shift ;;
    --prefix=*) PREFIX=${1#--prefix=} ;;
    --bin-dir) [ $# -ge 2 ] || die "--bin-dir needs a directory"; BIN_DIR=$2; shift ;;
    --bin-dir=*) BIN_DIR=${1#--bin-dir=} ;;
    --no-skill) SKILL=0 ;;
    --no-configure) CONFIGURE=0 ;;
    --agent-instructions) AGENT=--agent-instructions ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option '$1' (see --help)" ;;
  esac
  shift
done

case $PREFIX in /*) ;; *) die "--prefix must be an absolute path" ;; esac
case $BIN_DIR in /*) ;; *) die "--bin-dir must be an absolute path" ;; esac
command -v git >/dev/null 2>&1 || die "git is required"

if [ "$SCOPE" = local ]; then
  TOP=$(git rev-parse --show-toplevel 2>/dev/null) || die "--local must run inside a git repository"
  SKILL_DIR="$TOP/.claude/skills/$NAME"
else
  SKILL_DIR="$CLAUDE_DIR/skills/$NAME"
fi

# Copy only when content differs, so a second run is a no-op.
put() {  # put <src> <dst> <mode>
  if [ -f "$2" ] && cmp -s "$1" "$2"; then :; else cp "$1" "$2"; fi
  chmod "$3" "$2"
}

sh_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# ------------------------------------------------------------- uninstall ---
if [ "$UNINSTALL" = 1 ]; then
  if [ -x "$PREFIX/attribution" ]; then
    "$PREFIX/attribution" uninstall "--$SCOPE" || say "warning: 'attribution uninstall --$SCOPE' reported a problem"
  fi
  if [ -f "$SKILL_DIR/SKILL.md" ] && grep -q "^name: $NAME\$" "$SKILL_DIR/SKILL.md"; then
    rm -f "$SKILL_DIR/SKILL.md" "$SKILL_DIR/README.md"; rmdir "$SKILL_DIR" 2>/dev/null || :
    say "removed skill $SKILL_DIR"
  fi
  if [ "$SCOPE" = global ]; then
    if [ -f "$BIN_DIR/attribution" ] && grep -q "$MARKER" "$BIN_DIR/attribution"; then
      rm -f "$BIN_DIR/attribution"; say "removed $BIN_DIR/attribution"
    fi
    if [ -f "$PREFIX/$MARKER" ]; then
      rm -rf "$PREFIX"; say "removed $PREFIX"
    fi
  fi
  say "uninstalled ($SCOPE)"
  exit 0
fi

# --------------------------------------------------------------- install ---
for f in scripts/attribution scripts/core.sh scripts/patterns.sh scripts/hooks/_passthrough \
         scripts/hooks/commit-msg scripts/hooks/pre-commit scripts/hooks/pre-push SKILL.md VERSION; do
  [ -f "$SRC/$f" ] || die "missing $f; run install.sh from a complete checkout or release archive"
  if grep -q "$(printf '\r')" "$SRC/$f"; then
    die "$f has Windows (CRLF) line endings; re-clone with: git config --global core.autocrlf input"
  fi
done

if [ -e "$PREFIX" ] && [ ! -f "$PREFIX/$MARKER" ] && [ -n "$(ls -A "$PREFIX" 2>/dev/null)" ]; then
  die "$PREFIX exists and was not created by this installer; choose another --prefix"
fi

umask 022
mkdir -p "$PREFIX/hooks" "$BIN_DIR"
: > "$PREFIX/$MARKER"
put "$SRC/scripts/attribution" "$PREFIX/attribution" 755
put "$SRC/scripts/core.sh" "$PREFIX/core.sh" 644
put "$SRC/scripts/patterns.sh" "$PREFIX/patterns.sh" 644
put "$SRC/VERSION" "$PREFIX/VERSION" 644
for f in README.md LICENSE SKILL.md; do [ ! -f "$SRC/$f" ] || put "$SRC/$f" "$PREFIX/$f" 644; done
for h in _passthrough commit-msg pre-commit pre-push; do
  put "$SRC/scripts/hooks/$h" "$PREFIX/hooks/$h" 755
done

# Small wrapper instead of a symlink: works on Git Bash for Windows too.
wrapper=$(mktemp "${TMPDIR:-/tmp}/gag-wrapper.XXXXXX")
{
  printf '#!/bin/sh\n# %s wrapper (%s). Re-run install.sh to update.\n' "$NAME" "$MARKER"
  printf 'exec %s "$@"\n' "$(sh_quote "$PREFIX/attribution")"
} > "$wrapper"
put "$wrapper" "$BIN_DIR/attribution" 755
rm -f "$wrapper"
say "installed attribution $(cat "$SRC/VERSION") -> $PREFIX"
say "command: $BIN_DIR/attribution"

if [ "$SKILL" = 1 ]; then
  mkdir -p "$SKILL_DIR"
  put "$SRC/SKILL.md" "$SKILL_DIR/SKILL.md" 644
  [ ! -f "$SRC/README.md" ] || put "$SRC/README.md" "$SKILL_DIR/README.md" 644
  say "skill: $SKILL_DIR"
fi

if [ "$CONFIGURE" = 1 ]; then
  # shellcheck disable=SC2086
  "$PREFIX/attribution" install "--$SCOPE" $AGENT
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) say ""
     say "NOTE: $BIN_DIR is not on your PATH. Add this to your shell profile:"
     say "  export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac
say "done. Try: attribution status"
