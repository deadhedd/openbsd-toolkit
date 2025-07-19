#!/bin/sh
#
# test_all.sh – Run the full suite of tests, with optional centralized logging.
# Usage: ./test_all.sh [--log[=FILE]] [-h]
#

set -ex  # -e: exit on error; -x: trace commands

#
# 1) Locate this script’s real path
#
case "$0" in
  */*) SCRIPT_PATH="$0" ;;
  *)   SCRIPT_PATH="$(command -v -- "$0" 2>/dev/null || printf "%s" "$0")" ;;
esac
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"

#
# 2) Determine project root (strip /tests or /scripts if needed)
#
base="$(basename "$SCRIPT_DIR")"
if [ "$base" = "tests" ] || [ "$base" = "scripts" ]; then
  PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
else
  PROJECT_ROOT="$SCRIPT_DIR"
fi

TESTS_DIR="$PROJECT_ROOT/tests"

#
# 3) Logging defaults
#
FORCE_LOG=0
LOGFILE=""

#
# 4) Usage helper
#
usage() {
  cat <<EOF
Usage: $0 [--log[=FILE]] [-h]

  --log, -l       Capture stdout, stderr & xtrace into:
                   ${PROJECT_ROOT}/logs/$(basename "$0" .sh)-TIMESTAMP.log
                 Or use --log=FILE to choose a custom path.

  -h, --help      Show this help and exit.
EOF
  exit 0
}

#
# 5) Parse flags
#
while [ $# -gt 0 ]; do
  case "$1" in
    -l|--log)        FORCE_LOG=1             ;;
    -l=*|--log=*)    FORCE_LOG=1; LOGFILE="${1#*=}" ;;
    -h|--help)       usage                   ;;
    *)               echo "Unknown option: $1" >&2; usage ;;
  esac
  shift
done

#
# 6) Centralized logging init
#
LOG_HELPER="$PROJECT_ROOT/logs/logging.sh"
[ -f "$LOG_HELPER" ] || { echo "❌ logging.sh not found at $LOG_HELPER" >&2; exit 1; }
. "$LOG_HELPER"
init_logging "$0"

#
# 7) Verify test scripts exist
#
tests="test_system.sh test_obsidian_git.sh test_github.sh"
for t in $tests; do
  [ -f "$TESTS_DIR/$t" ] || { echo "Error: $t not found in $TESTS_DIR" >&2; exit 1; }
done

#
# 8) Run tests, buffer output, and handle logging
#
run_and_maybe_log() {
  TMP="$(mktemp)" || exit 1
  fail=0

  for t in $tests; do
    printf "⏳ Running %s …\n" "$t" >>"$TMP"
    if ! sh "$TESTS_DIR/$t" >>"$TMP" 2>&1; then
      printf "🛑 %s FAILED\n\n" "$t" >>"$TMP"
      fail=1
    else
      printf "✅ %s passed\n\n" "$t" >>"$TMP"
    fi
  done

  if [ "$fail" -ne 0 ]; then
    echo "🛑 Some tests FAILED — see full log in $LOGFILE"
    cat "$TMP" | tee "$LOGFILE"
    rm -f "$TMP"
    exit 1
  else
    if [ "$FORCE_LOG" -eq 1 ]; then
      echo "ℹ️  Tests passed — full log in $LOGFILE"
      cat "$TMP" >>"$LOGFILE"
    else
      cat "$TMP"
    fi
    rm -f "$TMP"
    echo "✅ All tests passed."
  fi
}

# 9) Execute
run_and_maybe_log

