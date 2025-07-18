#!/bin/sh
#
# logging.sh — centralized FIFO+tee logging helper
# Usage in your scripts:
#   FORCE_LOG=0; LOGFILE=""
#   parse --log / -l flags into those variables
#   . "$(dirname "$0")/logs/logging.sh"
#   init_logging "$0"
#

init_logging() {
  ORIGIN="$1"
  [ "${FORCE_LOG}" = 1 ] || return 0

  PROJECT_ROOT="$(cd "$(dirname -- "${ORIGIN}")" && pwd)"
  LOGDIR="$PROJECT_ROOT/logs"
  mkdir -p "$LOGDIR"

  # default log name if none provided
  if [ -z "$LOGFILE" ]; then
    BASENAME="$(basename "${ORIGIN}" .sh)"
    LOGFILE="$LOGDIR/${BASENAME}-$(date '+%Y%m%d_%H%M%S').log"
  fi

  echo "ℹ️  Logging to $LOGFILE"

  # FIFO in /tmp (must be a UNIX FS): use PID to avoid clashes
  FIFO="/tmp/$(basename "$ORIGIN" .sh)-$$.fifo"
  if mkfifo "$FIFO" 2>/dev/null; then
    tee -a "$LOGFILE" <"$FIFO" &
    exec >"$FIFO" 2>&1
    rm -f "$FIFO"
  else
    echo "⚠️  mkfifo failed (FAT32 or other); falling back to direct-to-log"
    exec >"$LOGFILE" 2>&1
  fi
}

