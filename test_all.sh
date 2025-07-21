#!/bin/sh
#
# test_all.sh — run tests for specified modules, or for enabled_modules.conf, or all modules.
# Usage: ./test_all.sh [--log[=FILE]] [-h] [module1 module2 ...]

set -x  # -e: exit on error; -x: trace commands

#
# 1) Locate this script’s real path
#
case "$0" in
  */*) SCRIPT_PATH="$0" ;;
  *)   SCRIPT_PATH="$(command -v -- "$0" 2>/dev/null || printf "%s" "$0")" ;;
esac
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"

#
# 2) Determine PROJECT_ROOT and MODULE_DIR
#
base="$(basename "$SCRIPT_DIR")"
if [ "$base" = "scripts" ]; then
  PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
else
  PROJECT_ROOT="$SCRIPT_DIR"
fi
MODULE_DIR="$PROJECT_ROOT/modules"
ENABLED_FILE="$PROJECT_ROOT/config/enabled_modules.conf"

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
Usage: $0 [--log[=FILE]] [-h] [module1 module2 ...]

  --log, -l       Capture full output to:
                    ${PROJECT_ROOT}/logs/$(basename "$0" .sh)-TIMESTAMP.log
                  Or use --log=FILE for a custom path.

  -h, --help      Show this help and exit.

If you list modules, only those are tested.
Else if $ENABLED_FILE exists, tests modules listed there.
Otherwise all modules under 'modules/' are tested.
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
    --)              shift; break            ;;
    -*)              echo "Unknown option: $1" >&2; usage ;;
    *)               break                   ;;
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
# 7) Prepare logfile if requested
#
if [ "$FORCE_LOG" -eq 1 ]; then
  if [ -z "$LOGFILE" ]; then
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    LOGFILE="$PROJECT_ROOT/logs/$(basename "$0" .sh)-$TIMESTAMP.log"
  fi
  mkdir -p "$(dirname "$LOGFILE")"
  echo "ℹ️  Logging all output to $LOGFILE"
fi

#
# 8) Determine which modules to test
#
if [ "$#" -gt 0 ]; then
  MODULES="$@"
elif [ -f "$ENABLED_FILE" ]; then
  MODULES="$(grep -Ev '^\s*(#|$)' "$ENABLED_FILE")"
else
  MODULES="$(for d in "$MODULE_DIR"/*; do [ -d "$d" ] && basename "$d"; done)"
fi

#
# 9) Run each module’s tests
#
TMP="$(mktemp)" || exit 1
fail=0

for mod in $MODULES; do
  DIR="$MODULE_DIR/$mod"

  # Find test script in module

  TEST="$DIR/test.sh"


  printf "⏳ Running tests for module '%s' …\n" "$mod" >>"$TMP"
  if ! sh "$TEST" >>"$TMP" 2>&1; then
    printf "🛑 Module '%s' FAILED\n\n" "$mod" >>"$TMP"
    fail=1
  else
    printf "✅ Module '%s' passed\n\n" "$mod" >>"$TMP"
  fi
done

#
# 10) Report results
#
if [ "$fail" -ne 0 ]; then
  echo "🛑 Some tests FAILED — see details below or in log." >&2
  if [ "$FORCE_LOG" -eq 1 ]; then
    cat "$TMP" | tee "$LOGFILE"
  else
    cat "$TMP"
  fi
  rm -f "$TMP"
  exit 1
else
  if [ "$FORCE_LOG" -eq 1 ]; then
    cat "$TMP" >>"$LOGFILE"
    echo "✅ All tests passed — full log in $LOGFILE"
  else
    cat "$TMP"
    echo "✅ All tests passed."
  fi
  rm -f "$TMP"
  exit 0
fi

