#!/bin/sh
#
# install_modules.sh - install specified modules, or all in config/enabled_modules.conf if none given
# Usage: ./install_modules.sh [--debug[=FILE]] [-h] [module1 module2 ...]

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
  Usage: $(basename "$0") [--debug[=FILE]] [-h] [module1 module2 ...]

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
# 4) Install base-system first (if present)
##############################################################################
# NOTE: This is actually dumb, remove it
echo "Installing prerequisite module: base-system"
sh "$MODULE_DIR/base-system/setup.sh" ${DBG_FLAG:+"$DBG_FLAG"}

##############################################################################
# 5) Install the rest
##############################################################################

for mod in $MODULES; do
  [ "$mod" = "base-system" ] && continue
  echo "Installing module: $mod"
  sh "$MODULE_DIR/$mod/setup.sh" ${DBG_FLAG:+"$DBG_FLAG"}
done

echo ""
echo "All requested modules installed!."
