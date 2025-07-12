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

  --log, -l           Capture everything (stdout, stderr, xtrace)
                      into a log file under ${SCRIPT_DIR}/logs.
                      If you do --log=FILE, that path is used instead.

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

# 5) Set up log directory & default file
LOGDIR="${SCRIPT_DIR}/logs"
if [ "$FORCE_LOG" -eq 1 ]; then
  mkdir -p "$LOGDIR"
  if [ -z "$LOGFILE" ]; then
    LOGFILE="$LOGDIR/setup_all-$(date '+%Y%m%d_%H%M%S').log"
  fi
  echo "ℹ️  Logging to $LOGFILE"

  # FIFO + tee trick
  FIFO="$LOGDIR/setup_all-$$.fifo"
  mkfifo "$FIFO"
  tee -a "$LOGFILE" <"$FIFO" &
  TEE_PID=$!

  # Redirect all output (incl. future xtrace) into our FIFO
  exec >"$FIFO" 2>&1
  rm -f "$FIFO"
fi

# 6) (Optional) if you want a trace of each command, uncomment:
# set -x

# 7) Run the three setup scripts
echo "👉 Running system setup…"
sh "$SCRIPT_DIR/setup_system.sh"

echo "👉 Running Obsidian-git setup…"
sh "$SCRIPT_DIR/setup_obsidian_git.sh"

echo "👉 Running GitHub setup…"
sh "$SCRIPT_DIR/setup_github.sh"

echo ""
echo "✅ All setup scripts completed successfully."

