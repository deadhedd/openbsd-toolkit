#!/bin/sh
#
# setup_all.sh - Run all three setup scripts in sequence
# Usage: ./setup_all.sh [--log[=FILE]] [-h]
#

set -x

# 1) Where this script lives
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 2) Logging defaults
FORCE_LOG=0
LOGFILE=""

# 3) Help text
usage() {
  cat <<EOF
Usage: $0 [--log[=FILE]] [-h]

  --log, -l           Capture stdout, stderr, and xtrace to a log file in:
                        ${SCRIPT_DIR}/logs/
                      Use --log=FILE to specify a custom path.

  -h, --help          Show this help and exit.
EOF
  exit 0
}

# 4) Parse flags
while [ $# -gt 0 ]; do
  case "$1" in
    -l|--log)
      FORCE_LOG=1
      ;;
    -l=*|--log=*)
      FORCE_LOG=1
      LOGFILE="${1#*=}"
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

# 5) Centralized logging init
. "$SCRIPT_DIR/logs/logging.sh"
init_logging "$0"

# 6) Turn on xtrace so everything shows up in the log
set -x

# 7) Run the three setup scripts
echo "👉 Running system setup…"
sh "$SCRIPT_DIR/setup_system.sh"

echo "👉 Running Obsidian-git setup…"
sh "$SCRIPT_DIR/setup_obsidian_git.sh"

echo "👉 Running GitHub setup…"
sh "$SCRIPT_DIR/setup_github.sh"

echo ""
echo "✅ All setup scripts completed successfully."

