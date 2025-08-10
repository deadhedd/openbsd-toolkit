#!/bin/sh
#
# test-all.sh — Run tests for specified modules, enabled_modules.conf, or all modules
# Author: deadhedd
# Version: 1.0.1
# Updated: 2025-08-10
#
# Usage: sh test-all.sh [--log[=FILE]] [--debug[=FILE]] [-h] [module1 module2 ...]
#
# Description:
#   Executes each selected module's test.sh and reports a pass/fail summary.
#   If no modules are specified, reads enabled_modules.conf; if that file is
#   absent, discovers all modules by scanning the modules/ directory.
#
# Deployment considerations:
#   Expects every module directory to contain an executable test.sh.
#   Forwards --debug or --log to individual module tests when supplied.
#
# Security note:
#   Enabling the --debug flag will log all executed commands *without* their
#   expanded values (test scripts use `set -x`). Setup scripts still capture
#   expansions via `set -vx`. Use caution when sharing or retaining debug logs.
#
# See also:
#   - modules/ (each module contains setup.sh and test.sh)
#   - install-modules.sh
#   - logs/logging.sh
#   - config/enabled_modules.conf
#   - config/load-secrets.sh

##############################################################################
# 0) Resolve paths
##############################################################################

case "$0" in
  *[!/]/*) SCRIPT_PATH="$0" ;;       # already has a slash
  *)        SCRIPT_PATH="$PWD/$0" ;; # relative -> assume cwd
esac
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

base="$(basename "$SCRIPT_DIR")"
if [ "$base" = "scripts" ]; then
  PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
else
  PROJECT_ROOT="$SCRIPT_DIR"
fi
MODULE_DIR="$PROJECT_ROOT/modules"
export PROJECT_ROOT MODULE_DIR

##############################################################################
# 1) Help / banned flags prescan
##############################################################################

show_help() {
  cat <<EOF
  Usage: sh $(basename "$0") [options]

  Description:
    Run test scripts for one or more modules (or all enabled modules by default)

  Options:
    -h, --help        Show this help message and exit
    -d, --debug       Enable debug mode (use --debug=FILE for custom file)
    -l, --log         Force log output (use --log=FILE for custom file)
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) show_help; exit 0 ;;
  esac
done

##############################################################################
# 2) Parse flags & init logging
##############################################################################

. "$PROJECT_ROOT/logs/logging.sh"
parse_logging_flags "$@"
eval "set -- $REMAINING_ARGS"
init_logging "test-all"

if [ "$DEBUG_MODE" -eq 1 ]; then
  echo "DEBUG(test-all): FORCE_LOG=$FORCE_LOG, DEBUG_MODE=$DEBUG_MODE, LOG_FILE='$LOG_FILE'" >&2
fi

# Flags to forward to module tests
FORWARD_FLAGS=""
if [ "$DEBUG_MODE" -eq 1 ]; then
  FORWARD_FLAGS="--debug"
elif [ "$FORCE_LOG" -eq 1 ]; then
  FORWARD_FLAGS="--log"
fi

##############################################################################
# 3) Determine module list
##############################################################################

if [ "$#" -gt 0 ]; then
  MODULES="$*"
  if [ "$DEBUG_MODE" -eq 1 ]; then
    echo "DEBUG(test-all): modules from args -> $MODULES" >&2
  fi
elif [ -f "$PROJECT_ROOT/config/enabled_modules.conf" ]; then
  MODULES="$(grep -Ev '^[[:space:]]*(#|$)' "$PROJECT_ROOT/config/enabled_modules.conf")"
  if [ "$DEBUG_MODE" -eq 1 ]; then
    echo "DEBUG(test-all): modules from enabled_modules.conf -> $MODULES" >&2
  fi
else
  MODULES="$(for d in "$MODULE_DIR"/*; do [ -d "$d" ] && basename "$d"; done)"
  if [ "$DEBUG_MODE" -eq 1 ]; then
    echo "DEBUG(test-all): modules from directory scan -> $MODULES" >&2
  fi
fi

##############################################################################
# 4) Run each module's tests
##############################################################################

fail=0
for mod in $MODULES; do
  echo "Running tests for '$mod' ..."
  if [ "$DEBUG_MODE" -eq 1 ]; then
    echo "DEBUG(test-all): invoking $MODULE_DIR/$mod/test.sh $FORWARD_FLAGS" >&2
  fi

  sh "$MODULE_DIR/$mod/test.sh" $FORWARD_FLAGS
  rc=$?
  if [ "$DEBUG_MODE" -eq 1 ]; then
    echo "DEBUG(test-all): '$mod' exited with $rc" >&2
  fi

  if [ "$rc" -ne 0 ]; then
    echo "!!! Module '$mod' FAILED"
    mark_test_failed
    fail=1
  else
    echo "Module '$mod' passed!"
  fi
done

##############################################################################
# 5) Summary & finalize logging
##############################################################################

if [ "$DEBUG_MODE" -eq 1 ]; then
  echo "DEBUG(test-all): overall fail status = $fail" >&2
fi
if [ "$fail" -ne 0 ]; then
  echo "Some tests FAILED - see log at $LOG_FILE"
else
  echo "All tests passed!"
fi

if [ "$DEBUG_MODE" -eq 1 ]; then
  echo "DEBUG(test-all): exiting with code $fail" >&2
  echo "DEBUG(test-all): calling finalize_logging" >&2
fi
finalize_logging
[ "$fail" -ne 0 ] && exit 1 || exit 0
