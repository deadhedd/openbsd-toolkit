#!/bin/sh
#
# setup_all.sh - Run all three setup scripts in sequence
# Usage: ./setup_all.sh [--log[=FILE]] [-h]
#

set -x

# 1) Where this script lives (even if you invoked via PATH or "sh setup_all.sh")
case "$0" in
  */*) SCRIPT_PATH="$0" ;;
  *)   SCRIPT_PATH="$(command -v -- "$0" 2>/dev/null || printf "%s" "$0")" ;;
esac
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"

# 2) Figure out project root vs scripts dir
if [ "$(basename "$SCRIPT_DIR")" = "scripts" ]; then
  PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
else
  PROJECT_ROOT="$SCRIPT_DIR"
fi
SCRIPTS_DIR="$PROJECT_ROOT/scripts"

# 3) Logging defaults
FORCE_LOG=0
LOGFILE=""

# 4) Help text
usage() {
  cat <<EOF
Usage: $0 [--log[=FILE]] [-h]

  --log, -l        Capture stdout, stderr & xtrace into:
                     ${PROJECT_ROOT}/logs/
                   Or use --log=FILE for a custom path.

  -h, --help       Show this help and exit.
EOF
  exit 0
}

# 5) Parse flags
while [ $# -gt 0 ]; do
  case "$1" in
    -l|--log)        FORCE_LOG=1             ;;
    -l=*|--log=*)    FORCE_LOG=1; LOGFILE="${1#*=}" ;;
    -h|--help)       usage                   ;;
    *)               echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# 6) Centralized logging init
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

# 7) Run the three setup scripts
echo "👉 Running system setup…"
sh "$SCRIPTS_DIR/setup_system.sh"

echo "👉 Running Obsidian-git setup…"
sh "$SCRIPTS_DIR/setup_obsidian_git.sh"

echo "👉 Running GitHub setup…"
sh "$SCRIPTS_DIR/setup_github.sh"

echo ""
echo "✅ All setup scripts completed successfully."

