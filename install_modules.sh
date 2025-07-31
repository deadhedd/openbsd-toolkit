#!/bin/sh
#
# install_modules.sh — Install specified modules, or all in enabled_modules.conf
# Author: deadhedd
# Version: 1.0.0
# Updated: 2025-07-28
#
# Usage: sh install_modules.sh [--debug[=FILE]] [-h] [module1 module2 ...]
#
# Description:
#   Runs each module's setup script in order. If no modules are given on the
#   command line, reads the list from config/enabled_modules.conf.
#
# Deployment considerations:
#   Expects PROJECT_ROOT/modules/*/setup.sh to exist and be executable.
#   Falls back to config/enabled_modules.conf when no args are provided.
#
# Security note:
#   Enabling the --debug flag will log all executed commands *and their expanded
#   values* (via `set -vx`), including any exported secrets or credentials.
#   Use caution when sharing or retaining debug logs.
#
# See also:
#   - modules/ (each module contains its own setup.sh and test.sh)
#   - test_all.sh
#   - logs/logging.sh
#   - config/enabled_modules.conf
#   - config/load-secrets.sh

##############################################################################
# 0) Resolve paths
##############################################################################

case "$0" in
  */*) SCRIPT_PATH="$0" ;;
  *)   SCRIPT_PATH="$(command -v -- "$0" 2>/dev/null || printf "%s" "$0")" ;;
esac
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"

if [ "$(basename "$SCRIPT_DIR")" = "scripts" ]; then
  PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
else
  PROJECT_ROOT="$SCRIPT_DIR"
fi
MODULE_DIR="$PROJECT_ROOT/modules"
ENABLED_FILE="$PROJECT_ROOT/config/enabled_modules.conf"
export PROJECT_ROOT

##############################################################################
# 1) Help & banned flags prescan
##############################################################################

usage() {
  cat <<EOF
  Usage: sh $(basename "$0") [--debug[=FILE]] [-h] [module1 module2 ...]

  Description:
    Install one or more module setups (or all enabled modules by default)

  Options:
    --debug, -d      Enable xtrace and capture all output (stdout/stderr/xtrace)
                   into logs/ (or into FILE if you do --debug=FILE).
    -h, --help       Show this help message and exit.

If no modules are specified, will install all in:
  $ENABLED_FILE
EOF
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      ;;
    -l|--log|-l=*|--log=*)
      printf '%s\n' "This script no longer supports --log. Did you mean --debug?" >&2
      exit 2
      ;;
  esac
done

##############################################################################
# 2) Debug/logging init
##############################################################################

DEBUG_MODE=0
DEBUG_LOGFILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--debug)
      DEBUG_MODE=1
      shift
      ;;
    -d=*|--debug=*)
      DEBUG_MODE=1
      DEBUG_LOGFILE="${1#*=}"
      shift
      ;;
    --) shift; break ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      ;;
    *) break ;;
  esac
done

if [ "$DEBUG_MODE" -eq 1 ]; then
  if [ -n "$DEBUG_LOGFILE" ]; then
    DBG_FLAG="--debug=$DEBUG_LOGFILE"
  else
    DBG_FLAG="--debug"
  fi
fi

# shellcheck source=logs/logging.sh
. "$PROJECT_ROOT/logs/logging.sh"
if [ "$DEBUG_MODE" -eq 1 ]; then
  set -vx
  init_logging "$(basename "$0" .sh)"
fi

##############################################################################
# 3) Determine module list
##############################################################################

if [ "$#" -gt 0 ]; then
  MODULES="$*"
else
  [ -f "$ENABLED_FILE" ] || {
    echo "!!! No modules specified and $ENABLED_FILE not found" >&2
    exit 1
  }
  MODULES="$(grep -Ev '^\s*(#|$)' "$ENABLED_FILE")"
fi

##############################################################################
# 4) Install all requested modules in order
##############################################################################

for mod in $MODULES; do
  echo "Installing module: $mod"
  sh "$MODULE_DIR/$mod/setup.sh" ${DBG_FLAG:+"$DBG_FLAG"}
done

echo ""
echo "All requested modules installed!."
