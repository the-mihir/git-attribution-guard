# shellcheck shell=sh disable=SC2034
# git-attribution-guard: shared logic for the CLI and the git hooks.
#
# The caller must set GAG_ROOT (directory that contains core.sh) before
# sourcing this file. Everything here is POSIX sh + POSIX awk.

# shellcheck source=scripts/patterns.sh
. "$GAG_ROOT/patterns.sh"

GAG_HOOKS_DIR="$GAG_ROOT/hooks"
GAG_MARK_BEGIN='# >>> git-attribution-guard >>>'
GAG_MARK_END='# <<< git-attribution-guard <<<'

# Hooks that only get a pass-through stub, so a global core.hooksPath never
# silently disables a repository's own hooks (git-lfs, gerrit, ...).
GAG_PASSTHROUGH_HOOKS='applypatch-msg pre-applypatch post-applypatch pre-merge-commit prepare-commit-msg post-commit pre-rebase post-checkout post-merge post-rewrite pre-auto-gc post-index-change reference-transaction push-to-checkout sendemail-validate'
GAG_MANAGED_HOOKS='commit-msg pre-commit pre-push'

# ---------------------------------------------------------------- output ---

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != dumb ]; then
  GAG_C_RED=$(printf '\033[31m'); GAG_C_GRN=$(printf '\033[32m')
  GAG_C_YEL=$(printf '\033[33m'); GAG_C_DIM=$(printf '\033[2m')
  GAG_C_BLD=$(printf '\033[1m');  GAG_C_OFF=$(printf '\033[0m')
else
  GAG_C_RED=; GAG_C_GRN=; GAG_C_YEL=; GAG_C_DIM=; GAG_C_BLD=; GAG_C_OFF=
fi

gag_err()  { printf '%s✖ %s%s\n' "$GAG_C_RED" "$*" "$GAG_C_OFF" >&2; }
gag_warn() { printf '%s! %s%s\n' "$GAG_C_YEL" "$*" "$GAG_C_OFF" >&2; }
gag_ok()   { printf '%s✔ %s%s\n' "$GAG_C_GRN" "$*" "$GAG_C_OFF" >&2; }
gag_note() { printf '%s  %s%s\n' "$GAG_C_DIM" "$*" "$GAG_C_OFF" >&2; }
gag_die()  { gag_err "$*"; exit 1; }

gag_tmp() {
  # Private temp file (umask 077). Callers remove it.
  (umask 077 && mktemp "${TMPDIR:-/tmp}/gag.XXXXXX") || gag_die "cannot create temp file"
}

gag_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# ---------------------------------------------------------------- config ---

gag_cfg() { git config --get "attribution.$1" 2>/dev/null; }

# gag_bool <key> <default>  -> prints true|false
gag_bool() {
  _v=$(git config --bool --get "attribution.$1" 2>/dev/null) || _v=$2
  [ -n "$_v" ] || _v=$2
  printf '%s' "$_v"
}

gag_mode() {
  _m=$(gag_cfg mode)
  case $_m in
    '') printf 'strip-ai' ;;
    strip-ai|allowlist|strip-all|off) printf '%s' "$_m" ;;
    *) gag_warn "invalid attribution.mode '$_m'; using strip-ai"; printf 'strip-ai' ;;
  esac
}

# Protection is active unless enabled=false or mode=off.
gag_enabled() {
  [ "$(gag_bool enabled true)" = true ] || return 1
  [ "$(gag_mode)" != off ]
}

gag_allow() { git config --get-all attribution.allow 2>/dev/null || :; }

gag_patterns() {
  printf '%s\n' "$GAG_BUILTIN_PATTERNS"
  git config --get-all attribution.extraPatterns 2>/dev/null || :
}

# ------------------------------------------------------------------- awk ---
# One awk program, three operations (op=filter|scan|ident). Patterns and
# allowlist arrive through ENVIRON so backslashes are never re-interpreted.

GAG_AWK='
function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function is_ai(s,   t, i) {
  t = " " tolower(s) " "
  for (i = 1; i <= npat; i++) if (t ~ pat[i]) return 1
  return 0
}
function email_of(v) {
  if (match(v, /<[^<>]*>/)) return tolower(trim(substr(v, RSTART + 1, RLENGTH - 2)))
  return ""
}
function is_allowed(e,   i, a) {
  if (e == "") return 0
  for (i = 1; i <= nallow; i++) {
    a = allow[i]
    if (e == a) return 1
    if (substr(a, 1, 1) == "@" && length(e) > length(a) && substr(e, length(e) - length(a) + 1) == a) return 1
  }
  return 0
}
# "" = keep the line, otherwise the reason it must go.
function verdict(line,   l, key, val, e, ai, ok, t) {
  l = line; sub(/\r$/, "", l)
  if (match(l, /^[ \t]*[A-Za-z][A-Za-z-]*[ \t]*:/)) {
    key = tolower(substr(l, RSTART, RLENGTH)); gsub(/[ \t:]/, "", key)
    val = substr(l, RSTART + RLENGTH)
    if (key == "co-authored-by" || key == "co-developed-by" || key == "assisted-by" || key == "signed-off-by" || key == "generated-by") {
      e = email_of(val); ai = is_ai(val); ok = is_allowed(e)
      if (key == "co-authored-by" || key == "co-developed-by") {
        if (mode == "strip-all") return "co-author (strip-all)"
        if (mode == "allowlist") return ok ? "" : "co-author not in allowlist"
        return (ai && !ok) ? "AI co-author" : ""
      }
      return (ai && !ok) ? "AI " key : ""
    }
  }
  t = tolower(l); sub(/^[^a-z0-9]+/, "", t)
  if (t ~ /^(generated|created|made|written|built|authored|assisted|coded|produced)[ \t]+(with|by|using|via)[ \t]/)
    if (index(l, "\360\237\244\226") || is_ai(l)) return "AI generated-with line"
  return ""
}
BEGIN {
  mode = ENVIRON["GAG_MODE"]; rmfile = ENVIRON["GAG_REMOVED_FILE"]
  n = split(ENVIRON["GAG_PATTERNS"], tmp, "\n")
  for (i = 1; i <= n; i++) {
    p = trim(tmp[i]); if (p == "" || substr(p, 1, 1) == "#") continue
    p = tolower(p); gsub(/\\b/, "[^a-z0-9]", p); pat[++npat] = p
  }
  n = split(ENVIRON["GAG_ALLOW"], tmp, "\n")
  for (i = 1; i <= n; i++) { a = tolower(trim(tmp[i])); if (a != "") allow[++nallow] = a }
  if (op == "scan") RS = "\036"
}
op == "ident" { print ((is_ai($0) && !is_allowed(email_of($0))) ? "ai" : "ok"); next }
op == "filter" {
  if (scissors) { out[++no] = $0; next }
  if ($0 ~ /^[^ \t] -+ >8 -+\r?$/) {
    scissors = 1; if (seen && blanks) out[++no] = ""
    blanks = 0; out[++no] = $0; next
  }
  r = verdict($0)
  if (r != "") { removed++; if (rmfile != "") print trim($0) "\t" r > rmfile; next }
  if ($0 ~ /^[ \t\r]*$/) { blanks++; next }
  if (seen && blanks) out[++no] = ""
  blanks = 0; seen = 1; out[++no] = $0; next
}
op == "scan" {
  nl = split($0, L, "\n"); h = 1
  while (h <= nl && L[h] == "") h++
  if (h > nl) next
  split(L[h], H, "\037"); sha = H[1]; au = H[2]; cm = H[3]
  if (is_ai(au) && !is_allowed(email_of(au))) print sha "\tAI author\t" au
  if (cm != au && is_ai(cm) && !is_allowed(email_of(cm))) print sha "\tAI committer\t" cm
  for (i = h + 1; i <= nl; i++) { r = verdict(L[i]); if (r != "") print sha "\t" r "\t" trim(L[i]) }
}
END {
  if (op == "filter") {
    if (!removed) exit 3
    for (i = 1; i <= no; i++) print out[i]
  }
}
'

# gag_awk <op> [awk file args...]; honours GAG_MODE / GAG_REMOVED_FILE env.
gag_awk() {
  _op=$1; shift
  GAG_PATTERNS=$(gag_patterns) GAG_ALLOW=$(gag_allow) GAG_MODE=${GAG_MODE:-$(gag_mode)} \
    LC_ALL=C awk -v op="$_op" "$GAG_AWK" "$@"
}

# "Name <email>" -> exit 0 when it is an AI/bot identity that is not allowed.
gag_ident_is_ai() {
  [ "$(printf '%s\n' "$1" | gag_awk ident)" = ai ]
}

# gag_filter_msg <in> <out> -> 0 changed (out written), 3 unchanged, else error.
gag_filter_msg() {
  gag_awk filter "$1" > "$2"
}

# Rewrite a commit message file in place. Idempotent.
gag_filter_file() {
  _f=$1; _t=$(gag_tmp); _r=$(gag_tmp)
  GAG_REMOVED_FILE=$_r gag_filter_msg "$_f" "$_t"; _rc=$?
  if [ "$_rc" -eq 0 ]; then
    cat "$_t" > "$_f" || { rm -f "$_t" "$_r"; gag_die "cannot write $_f"; }
    printf '%sgit-attribution-guard: removed from commit message (mode: %s):%s\n' "$GAG_C_DIM" "$(gag_mode)" "$GAG_C_OFF" >&2
    while IFS= read -r _l; do printf '%s  - %s%s\n' "$GAG_C_DIM" "${_l%%	*}" "$GAG_C_OFF" >&2; done < "$_r"
    _rc=0
  elif [ "$_rc" -eq 3 ]; then
    _rc=0
  else
    gag_err "git-attribution-guard: failed to filter commit message (check attribution.extraPatterns)"
  fi
  rm -f "$_t" "$_r"
  return "$_rc"
}

# gag_scan <git log args...>: prints "sha<TAB>reason<TAB>detail" lines.
gag_scan() {
  git -c log.showSignature=false log --no-color \
    --format='%x1e%H%x1f%an <%ae>%x1f%cn <%ce>%n%B' "$@" | gag_awk scan
}

# Pretty-print scan output (stdin), grouped by commit.
gag_print_findings() {
  _last=
  while IFS='	' read -r _sha _why _what; do
    if [ "$_sha" != "$_last" ]; then
      printf '  %s%s%s %s\n' "$GAG_C_BLD" "$(printf '%s' "$_sha" | cut -c1-12)" "$GAG_C_OFF" \
        "$(git log -1 --format=%s "$_sha" 2>/dev/null)"
      _last=$_sha
    fi
    printf '      %s%s%s  %s(%s)%s\n' "$GAG_C_RED" "$_what" "$GAG_C_OFF" "$GAG_C_DIM" "$_why" "$GAG_C_OFF"
  done
}

# ----------------------------------------------------------------- paths ---

gag_canon() { (CDPATH='' cd -- "$1" 2>/dev/null && pwd -P); }

gag_common_dir() {
  _d=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  gag_canon "$_d"
}

# -------------------------------------------------------------- chaining ---

# Directory whose hooks git would have run without us.
gag_chain_dir() {
  _p=$(git config --path --get attribution.previousHooksPath 2>/dev/null)
  if [ -n "$_p" ] && [ -d "$_p" ]; then printf '%s' "$_p"; return 0; fi
  _c=$(gag_common_dir) || return 1
  printf '%s/hooks' "$_c"
}

# gag_chain <hook> [args...]: run the repository's own hook, if any.
# stdin is inherited. Returns the chained hook's exit code.
gag_chain() {
  _name=$1; shift
  _dir=$(gag_chain_dir) || return 0
  _dc=$(gag_canon "$_dir") || return 0
  [ "$_dc" != "$(gag_canon "$GAG_HOOKS_DIR")" ] || return 0   # never call ourselves
  _hook="$_dc/$_name"
  [ -f "$_hook" ] && [ -x "$_hook" ] || return 0
  "$_hook" "$@"
}

# ----------------------------------------------------------------- hooks ---

gag_check_author() {
  gag_enabled || return 0
  _ident=$(git var GIT_AUTHOR_IDENT 2>/dev/null) || return 0
  _name=${_ident%% <*}
  _email=${_ident#*<}; _email=${_email%%>*}
  if gag_ident_is_ai "$_name <$_email>"; then
    gag_err "git-attribution-guard: commit author looks like an AI/bot: $_name <$_email>"
    gag_note "fix:  git config user.name \"Your Name\" && git config user.email you@example.com"
    gag_note "or allow it: attribution allow add $_email"
    return 1
  fi
  _xe=$(gag_cfg authorEmail); _xn=$(gag_cfg authorName)
  [ -n "$_xe$_xn" ] || return 0
  _bad=0
  if [ -n "$_xe" ] && [ "$(gag_lower "$_xe")" != "$(gag_lower "$_email")" ]; then _bad=1; fi
  if [ -n "$_xn" ] && [ "$_xn" != "$_name" ]; then _bad=1; fi
  [ "$_bad" -eq 1 ] || return 0
  gag_err "git-attribution-guard: commit author does not match the expected identity"
  gag_note "current:  $_name <$_email>"
  gag_note "expected: ${_xn:-$_name} <${_xe:-$_email}>"
  gag_note "fix:      git config user.name \"${_xn:-$_name}\" && git config user.email \"${_xe:-$_email}\""
  gag_note "one-off:  git commit --author=\"${_xn:-$_name} <${_xe:-$_email}>\""
  gag_note "disable:  attribution author clear [--local]"
  return 1
}

gag_is_zero() { case $1 in *[!0]*) return 1 ;; *) return 0 ;; esac; }

# gag_prepush <remote-name> ; ref lines on stdin.
gag_prepush() {
  gag_enabled || { cat > /dev/null; return 0; }
  [ "$(gag_bool blockPush true)" = true ] || { cat > /dev/null; return 0; }
  _remote=$1; _out=$(gag_tmp)
  while read -r _lref _lsha _rref _rsha; do
    [ -n "${_lsha:-}" ] || continue
    gag_is_zero "$_lsha" && continue                        # branch deletion
    if [ -n "${_rsha:-}" ] && ! gag_is_zero "$_rsha" && git cat-file -e "$_rsha^{commit}" 2>/dev/null; then
      gag_scan "$_rsha..$_lsha" >> "$_out"                  # update
    else
      gag_scan "$_lsha" --not --remotes="$_remote" >> "$_out"  # new branch / unknown remote tip
    fi
  done
  if [ -s "$_out" ]; then
    gag_err "git-attribution-guard: push blocked, disallowed attribution (mode: $(gag_mode)):"
    sort -u "$_out" | awk -F '\t' '!s[$1]++ { o[++n] = $1 } { l[$1] = l[$1] $0 "\n" } END { for (i = 1; i <= n; i++) printf "%s", l[o[i]] }' | gag_print_findings >&2
    gag_note "fix the history:  attribution rewrite <range> --dry-run   (then without --dry-run)"
    gag_note "or amend the last commit:  git commit --amend"
    gag_note "bypass once (not recommended):  git push --no-verify"
    rm -f "$_out"; return 1
  fi
  rm -f "$_out"; return 0
}

# gag_hook_main <hook-name> <chain:1|0> [git hook args...]
gag_hook_main() {
  _hname=$1; _chain=$2; shift 2
  case $_hname in
    commit-msg)
      if [ "$_chain" = 1 ]; then gag_chain commit-msg "$@" || exit $?; fi
      gag_enabled || exit 0
      [ -n "${1:-}" ] || gag_die "commit-msg: missing message file"
      gag_filter_file "$1" || exit 1
      ;;
    pre-commit)
      gag_check_author || exit 1
      if [ "$_chain" = 1 ]; then gag_chain pre-commit "$@" || exit $?; fi
      ;;
    pre-push)
      _in=$(gag_tmp)
      cat > "$_in"
      gag_prepush "${1:-origin}" < "$_in" || { rm -f "$_in"; exit 1; }
      if [ "$_chain" = 1 ]; then
        gag_chain pre-push "$@" < "$_in"; _rc=$?
        rm -f "$_in"; exit "$_rc"
      fi
      rm -f "$_in"
      ;;
    *)
      [ "$_chain" = 1 ] || exit 0
      gag_chain "$_hname" "$@"; exit $?
      ;;
  esac
  exit 0
}
