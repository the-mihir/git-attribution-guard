#!/bin/sh
# Test runner: ./tests/run.sh [test-file-pattern]
# Every test_* function runs in its own subshell with a fresh sandbox HOME.
set -u
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
BASE_PATH=$PATH
export BASE_PATH
pass=0; failed=0; skipped=0; failed_names=

for file in "$HERE"/test_*.sh; do
  case $file in *"${1:-}"*) ;; *) continue ;; esac
  printf '%s\n' "$(basename "$file")"
  # shellcheck disable=SC2013
  for t in $(sed -n 's/^\(test_[a-z0-9_]*\)() *{.*/\1/p' "$file"); do
    out=$( {
      # shellcheck source=tests/lib.sh
      . "$HERE/lib.sh"
      # shellcheck disable=SC1090
      . "$file"
      setup
      "$t"
      rc=$?
      teardown
      [ "$rc" -eq 77 ] && exit 77
      [ "$FAILS" -eq 0 ]
    } 2>&1 )
    rc=$?
    if [ "$rc" -eq 0 ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$t"
    elif [ "$rc" -eq 77 ]; then skipped=$((skipped + 1)); printf '  skip  %s %s\n' "$t" "$(printf '%s' "$out" | tail -n1)"
    else failed=$((failed + 1)); failed_names="$failed_names $t"; printf '  FAIL  %s\n%s\n' "$t" "$out"; fi
  done
done

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$failed" "$skipped"
[ "$failed" -eq 0 ] || { printf 'failed:%s\n' "$failed_names"; exit 1; }
