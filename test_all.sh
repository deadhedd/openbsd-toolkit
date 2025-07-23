#!/bin/sh
#
# test_all.sh — run tests for specified modules, or for enabled_modules.conf, or all modules.
# Usage: ./test_all.sh [--log[=FILE]] [--debug] [-h] [module1 module2 ...]

# 1) Locate this script’s real path
case "$0" in
  *[!/]/*) SCRIPT_PATH="$0" ;;       # already has a slash
  *)        SCRIPT_PATH="$PWD/$0" ;; # relative → assume cwd
esac
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

# 2) Determine PROJECT_ROOT and MODULE_DIR
base="$(basename "$SCRIPT_DIR")"
if [ "$base" = "scripts" ]; then
  PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
else
  PROJECT_ROOT="$SCRIPT_DIR"
fi
MODULE_DIR="$PROJECT_ROOT/modules"
export PROJECT_ROOT MODULE_DIR

# 3) Source logging library, parse flags & init
. "$PROJECT_ROOT/logs/logging.sh"
parse_logging_flags "$@"
eval "set -- $REMAINING_ARGS"
init_logging "test-all"

echo "DEBUG(test_all): FORCE_LOG=$FORCE_LOG, DEBUG_MODE=$DEBUG_MODE, LOG_FILE='$LOG_FILE'" >&3

# decide what flags to forward to each module test
FORWARD_FLAGS=""
if [ "$DEBUG_MODE" -eq 1 ]; then
  FORWARD_FLAGS="--debug"
elif [ "$FORCE_LOG" -eq 1 ]; then
  FORWARD_FLAGS="--log"
fi

# 4) Determine which modules to test
if [ "$#" -gt 0 ]; then
  MODULES="$@"
  echo "DEBUG(test_all): modules from args -> $MODULES" >&3
elif [ -f "$PROJECT_ROOT/config/enabled_modules.conf" ]; then
  MODULES="$(grep -Ev '^[[:space:]]*(#|$)' "$PROJECT_ROOT/config/enabled_modules.conf")"
  echo "DEBUG(test_all): modules from enabled_modules.conf -> $MODULES" >&3
else
  MODULES="$(for d in "$MODULE_DIR"/*; do [ -d "$d" ] && basename "$d"; done)"
  echo "DEBUG(test_all): modules from directory scan -> $MODULES" >&3
fi

# 5) Run each module’s tests
fail=0
for mod in $MODULES; do
  echo "⏳ Running tests for '$mod' …"
  echo "DEBUG(test_all): invoking $MODULE_DIR/$mod/test.sh $FORWARD_FLAGS" >&3

  sh "$MODULE_DIR/$mod/test.sh" $FORWARD_FLAGS
  rc=$?
  echo "DEBUG(test_all): '$mod' exited with $rc" >&3

  if [ "$rc" -ne 0 ]; then
    echo "🛑 Module '$mod' FAILED"
    mark_test_failed
    fail=1
  else
    echo "✅ Module '$mod' passed"
  fi
done

# 6) Summary
echo "DEBUG(test_all): overall fail status = $fail" >&3
if [ "$fail" -ne 0 ]; then
  echo "🛑 Some tests FAILED — see log at $LOG_FILE"
else
  echo "✅ All tests passed"
fi

# 7) Finalize logging
echo "DEBUG(test_all): calling finalize_logging" >&3
finalize_logging

# 8) Exit with status
echo "DEBUG(test_all): exiting with code $fail" >&3
[ "$fail" -ne 0 ] && exit 1 || exit 0
