#!/bin/sh
#
# logs/logging.sh — Centralized logging & debug helpers (sourced utility)
# Author: deadhedd
# Version: 1.0.0
# Updated: 2025-08-02
#
# Usage:
#   . "$PROJECT_ROOT/logs/logging.sh"
#   start_logging "<context-name>" "$@"        # for test scripts
#   start_logging_if_debug "<context-name>" "$@"  # for setup scripts
#   ... your logic ...
#   [tests only] finalize_logging
#
# Description:
#   Provides a common flag parser (--log/--debug), sets up stdout/stderr
#   redirection to temp or permanent log files, and exposes helpers for test
#   failure tracking and cleanup.
#
# Deployment considerations:
#   Intended to be sourced. Direct execution may behave unexpectedly.
#   FD 3 is reserved for real stdout so debug messages can bypass redirection.
#
# Security note:
#   Enabling the --debug flag will log all executed commands. Setup scripts also
#   log their expanded values (via `set -vx`), which may include exported secrets
#   or credentials. Use caution when sharing or retaining debug logs.
#
# See also:
#   - config/load-secrets.sh
#   - logs/ (for generated log files)

##############################################################################
# 1) FD setup & globals
##############################################################################

exec 3>&-     # Ensure any leftover fd 3 is closed
exec 3>&1     # Make fd 3 point at the real stdout for debug messages

FORCE_LOG=${FORCE_LOG:-0}
DEBUG_MODE=${DEBUG_MODE:-0}
LOG_FILE=${LOG_FILE:-}
LOG_TMP=${LOG_TMP:-}
TEST_FAILED=${TEST_FAILED:-0}
REMAINING_ARGS=${REMAINING_ARGS:-}

##############################################################################
# 2) Flag parser: --log / --debug
##############################################################################

parse_logging_flags() {
  raw_args="$*"
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
      --debug=*)
        DEBUG_MODE=1
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

  REMAINING_ARGS="$*"
  export FORCE_LOG DEBUG_MODE LOG_FILE TEST_FAILED REMAINING_ARGS

  if [ "$DEBUG_MODE" -eq 1 ]; then
    echo "DEBUG(parse_logging_flags): raw args=$raw_args" >&2
    echo "DEBUG(parse_logging_flags): FORCE_LOG=$FORCE_LOG, DEBUG_MODE=$DEBUG_MODE, LOG_FILE='$LOG_FILE'" >&2
  fi
}

##############################################################################
# 2.5) Convenience wrappers
##############################################################################

# start_logging <context> [args...]
#   Parse logging flags from the provided args, replace "$@" with remaining
#   arguments, and initialize logging with the given context. Debug mode also
#   enables shell tracing.
start_logging() {
  context="$1"
  shift
  parse_logging_flags "$@"
  eval "set -- $REMAINING_ARGS"
  if { [ "$FORCE_LOG" -eq 1 ] || [ "$DEBUG_MODE" -eq 1 ]; } && [ -z "$LOGGING_INITIALIZED" ]; then
    mod="$(basename "$(dirname "$context")")"
    init_logging "${mod}-$(basename "$context")"
  else
    init_logging "$context"
  fi
  trap finalize_logging EXIT
  [ "$DEBUG_MODE" -eq 1 ] && set -x
}

# start_logging_if_debug <context> [args...]
#   Same as start_logging, but only initializes logging when --debug was
#   provided. Useful for setup scripts that normally run without logging.
start_logging_if_debug() {
  context="$1"
  shift
  parse_logging_flags "$@"
  eval "set -- $REMAINING_ARGS"
  if [ "$DEBUG_MODE" -eq 1 ]; then
    init_logging "$context"
    set -vx
  fi
}

##############################################################################
# 3) Debug/logging init
##############################################################################

init_logging() {
  context="$1"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(init_logging): context='$context'" >&2

  # Derive PROJECT_ROOT if not pre-set
  if [ -z "$PROJECT_ROOT" ]; then
    SCRIPT_PATH="$0"
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    base="$(basename "$SCRIPT_DIR")"
    if [ "$base" = "scripts" ]; then
      PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    else
      PROJECT_ROOT="$SCRIPT_DIR"
    fi
  else
    [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(init_logging): PROJECT_ROOT pre-set to '$PROJECT_ROOT'" >&2
  fi
  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(init_logging): PROJECT_ROOT='$PROJECT_ROOT'" >&2

  LOG_DIR="$PROJECT_ROOT/logs"
  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(init_logging): creating LOG_DIR='$LOG_DIR'" >&2
  mkdir -p "$LOG_DIR"  # TODO: use state detection for idempotency

  if [ -z "$LOG_FILE" ]; then
    timestamp="$(date '+%Y%m%d_%H%M%S')"

    # if context contains a path, use its parent dir as module name
    if echo "$context" | grep -q '/'; then
      mod="$(basename "$(dirname "$context")")"
      name="$(basename "$context" .sh)"
      base_context="${mod}-${name}"
    else
      base_context="$(basename "$context" .sh)"
    fi

    LOG_FILE="$LOG_DIR/${base_context}-${timestamp}.log"
    [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(init_logging): default LOG_FILE='$LOG_FILE'" >&2
  else
    [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(init_logging): provided LOG_FILE='$LOG_FILE'" >&2
  fi
  export LOG_FILE

  if [ "$FORCE_LOG" -eq 1 ]; then
    [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(init_logging): redirecting output to '$LOG_FILE'" >&2
    [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(init_logging): enabling xtrace" >&2 && set -x
    exec >>"$LOG_FILE" 2>&1  # TODO: use state detection for idempotency
  else
    LOG_TMP="$(mktemp /tmp/logtmp.XXXXXXXX)"  # TODO: use state detection for idempotency
    [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(init_logging): buffering into '$LOG_TMP'" >&2
    export LOG_TMP
    exec >"$LOG_TMP" 2>&1  # TODO: use state detection for idempotency
  fi

  export LOGGING_INITIALIZED=1
}

##############################################################################
# 4) Test helpers
##############################################################################

mark_test_failed() {
  TEST_FAILED=1
  export TEST_FAILED
  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(mark_test_failed): TEST_FAILED=1" >&2
}

finalize_logging() {
  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(finalize_logging): DM=$DEBUG_MODE, FL=$FORCE_LOG, TF=$TEST_FAILED" >&2

  if [ "$DEBUG_MODE" -eq 1 ] || [ "$FORCE_LOG" -eq 1 ] || [ "$TEST_FAILED" -eq 1 ]; then
    if [ -n "$LOG_TMP" ] && [ -f "$LOG_TMP" ]; then
      [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(finalize_logging): appending '$LOG_TMP' to '$LOG_FILE'" >&2
      cat "$LOG_TMP" >>"$LOG_FILE"  # TODO: use state detection for idempotency
      rm -f "$LOG_TMP"
      [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(finalize_logging): removed temp file" >&2
    fi
    echo "Logs written to $LOG_FILE" >&3
  else
    [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(finalize_logging): removing temp file '$LOG_TMP'" >&2
    rm -f "$LOG_TMP"
  fi
  exec 1>&3 2>&3   # Restore stdout/stderr for any further output
  exec 3>&-        # Close the debug descriptor
}
