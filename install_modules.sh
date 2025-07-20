#!/bin/sh
#
# install_modules.sh — install specified modules, or all in config/enabled_modules.conf if none given
# Usage: ./install_modules.sh [--log[=FILE]] [-h] [module1 module2 ...]

set -x

#
# 1) Figure out where this script lives
#
case "$0" in
  */*) SCRIPT_PATH="$0" ;;
  *)   SCRIPT_PATH="$(command -v -- "$0" 2>/dev/null || printf "%s" "$0")" ;;
esac
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"

#
# 2) Determine PROJECT_ROOT, MODULE_DIR, and enabled‑modules file
#
if [ "$(basename "$SCRIPT_DIR")" = "scripts" ]; then
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
# 4) Help text
#
usage() {
  cat <<EOF
Usage: $0 [--log[=FILE]] [-h] [module1 module2 ...]

  --log, -l        Capture stdout, stderr & xtrace into:
                     ${PROJECT_ROOT}/logs/
                   Or use --log=FILE for a custom path.

  -h, --help       Show this help and exit.

If no modules are specified, will install all in:
  $ENABLED_FILE
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
    -*)
      echo "Unknown option: $1" >&2
      usage
      ;;
    *) break ;;
  esac
  shift
done

#
# 6) Logging init (your existing helper)
#
if   [ -f "$PROJECT_ROOT/logs/logging.sh" ]; then
  LOG_HELPER="$PROJECT_ROOT/logs/logging.sh"
elif [ -f "$PROJECT_ROOT/../logs/logging.sh" ]; then
  LOG_HELPER="$PROJECT_ROOT/../logs/logging.sh"
else
  echo "❌ logging.sh not found in logs/ or ../logs/" >&2
  exit 1
fi
. "$LOG_HELPER"
init_logging "$0"

#
# 7) Determine module list
#
if [ "$#" -gt 0 ]; then
  MODULES="$@"
else
  if [ ! -f "$ENABLED_FILE" ]; then
    echo "❌ No modules specified and $ENABLED_FILE not found" >&2
    exit 1
  fi
  MODULES="$(grep -Ev '^\s*(#|$)' "$ENABLED_FILE")"
fi

#
# 8) Always install base-system first (if present)
#
if [ -x "$MODULE_DIR/base-system/setup_system.sh" ]; then
  echo "🔧 Installing prerequisite module: base-system"
  sh "$MODULE_DIR/base-system/setup_system.sh"
else
  echo "⚠️  base-system setup not found or not executable; skipping prereq"
fi

#
# 9) Install the rest of the modules
#
for mod in $MODULES; do
  [ "$mod" = "base-system" ] && continue

  DIR="$MODULE_DIR/$mod"
  # pick the setup script (generic or fallback)
  if [ -x "$DIR/setup.sh" ]; then
    SETUP="$DIR/setup.sh"
  else
    SETUP="$(ls "$DIR"/setup_*.sh 2>/dev/null | head -n1)"
  fi

  if [ -z "$SETUP" ] || [ ! -x "$SETUP" ]; then
    echo "❌ Skipping '$mod': no executable setup script found"
    continue
  fi

  echo "👉 Installing module: $mod"
  sh "$SETUP"
done

echo ""
echo "✅ All requested modules installed."

