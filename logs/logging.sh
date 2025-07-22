#!/bin/sh
#
# logging.sh — POSIX‑compliant centralized logging & debug helper
#
# Usage in your scripts (test or setup):
#   . "$(dirname "$0")/logging.sh"
#   set -- $(parse_logging_flags "$@")   # strip out --log/--debug
#   init_logging "<context-name>"
#   … your logic …
#   [if test script] finalize_logging

#--------------------------------------------------
# Make fd 3 point at the real stdout for debug messages
exec 3>&1

# Defaults
FORCE_LOG=0
DEBUG_MODE=0
LOG_FILE=""
LOG_TMP=""
TEST_FAILED=0

#--------------------------------------------------
# Parse --log / --debug flags
# Outputs leftover args for caller’s `set --`
parse_logging_flags() {
  echo "DEBUG(parse_logging_flags): raw args=$*" >&3
  while [ $# -gt 0 ]; do
    case "$1" in
      --log|-l)
        FORCE_LOG=1
        shift
        ;;
      --log=*)
        FORCE_LOG=1
        LOG_FILE="${1#*=}"
        shift
        ;;
      --debug)
        DEBUG_MODE=1
        FORCE_LOG=1
        shift
        ;;
      *) break ;;
    esac
  done
  echo "DEBUG(parse_logging_flags): FORCE_LOG=$FORCE_LOG, DEBUG_MODE=$DEBUG_MODE, LOG_FILE='$LOG_FILE'" >&3
  export FORCE_LOG DEBUG_MODE LOG_FILE TEST_FAILED
  echo "$@"
}

#--------------------------------------------------
# Initialize logging: respect a pre‑set PROJECT_ROOT or derive it, then choose logfile or buffer
init_logging() {
  context="$1"
  echo "DEBUG(init_logging): context='$context'" >&3

  # If the caller has already exported PROJECT_ROOT, keep it; otherwise derive it
  if [ -n "$PROJECT_ROOT" ]; then
    echo "DEBUG(init_logging): PROJECT_ROOT pre‑set to '$PROJECT_ROOT' (keeping it)" >&3
  else
    SCRIPT_PATH="$0"
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    base="$(basename "$SCRIPT_DIR")"
    if [ "$base" = "scripts" ]; then
      PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    else
      PROJECT_ROOT="$SCRIPT_DIR"
    fi
  fi
  echo "DEBUG(init_logging): PROJECT_ROOT='$PROJECT_ROOT'" >&3

  LOG_DIR="$PROJECT_ROOT/logs"
  echo "DEBUG(init_logging): creating LOG_DIR='$LOG_DIR'" >&3
  mkdir -p "$LOG_DIR"

  if [ -z "$LOG_FILE" ]; then
    timestamp="$(date '+%Y%m%d_%H%M%S')"
    LOG_FILE="$LOG_DIR/${context}-${timestamp}.log"
    echo "DEBUG(init_logging): default LOG_FILE='$LOG_FILE'" >&3
  else
    echo "DEBUG(init_logging): provided LOG_FILE='$LOG_FILE'" >&3
  fi
  export LOG_FILE

  if [ "$DEBUG_MODE" -eq 1 ] || [ "$FORCE_LOG" -eq 1 ]; then
    echo "DEBUG(init_logging): redirecting all output to '$LOG_FILE'" >&3
    exec >"$LOG_FILE" 2>&1
    [ "$DEBUG_MODE" -eq 1 ] && { echo "DEBUG(init_logging): enabling xtrace" >&3; set -x; }
  else
    LOG_TMP="$(mktemp /tmp/logtmp.XXXXXXXX)"
    echo "DEBUG(init_logging): buffering into temp file '$LOG_TMP'" >&3
    export LOG_TMP
    exec >"$LOG_TMP" 2>&1
  fi
}

#--------------------------------------------------
# Mark that a test has failed
mark_test_failed() {
  TEST_FAILED=1
  echo "DEBUG(mark_test_failed): TEST_FAILED=1" >&3
  export TEST_FAILED
}

#--------------------------------------------------
# Finalize logging at end of test script
finalize_logging() {
  echo "DEBUG(finalize_logging): DM=$DEBUG_MODE, FL=$FORCE_LOG, TF=$TEST_FAILED" >&3
  if [ "$DEBUG_MODE" -eq 1 ] || [ "$FORCE_LOG" -eq 1 ] || [ "$TEST_FAILED" -eq 1 ]; then
    if [ -n "$LOG_TMP" ] && [ -f "$LOG_TMP" ]; then
      echo "DEBUG(finalize_logging): appending '$LOG_TMP' to '$LOG_FILE'" >&3
      cat "$LOG_TMP" >>"$LOG_FILE"
      rm -f "$LOG_TMP"
      echo "DEBUG(finalize_logging): removed temp file" >&3
    fi
    echo "Logs written to $LOG_FILE" >&3
  else
    echo "DEBUG(finalize_logging): removing temp file '$LOG_TMP'" >&3
    rm -f "$LOG_TMP"
  fi
}
