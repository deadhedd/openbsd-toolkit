#!/bin/sh
#
# logging.sh — FIFO+tee logging helper
# Usage in your script:
#   1. Set FORCE_LOG and LOGFILE (empty or custom)
#   2. Call: init_logging "$0"
#

init_logging() {
  ORIGIN="$1"
  [ "${FORCE_LOG}" = 1 ] || return 0

  # Determine project root (dirname of the calling script)
  PROJECT_ROOT="$(cd "$(dirname -- "${ORIGIN}")" && pwd)"
  LOGDIR="$PROJECT_ROOT/logs"
  mkdir -p "$LOGDIR"

  # Default logfile name if none supplied
  if [ -z "$LOGFILE" ]; then
    BASENAME="$(basename "${ORIGIN}" .sh)"
    LOGFILE="$LOGDIR/${BASENAME}-$(date '+%Y%m%d_%H%M%S').log"
  fi

  echo "ℹ️  Logging to $LOGFILE"

  # Create FIFO, start tee, redirect everything into it
  FIFO="$LOGDIR/logpipe-$$.fifo"
  mkfifo "$FIFO"
  tee -a "$LOGFILE" < "$FIFO" &
  TEE_PID=$!
  exec > "$FIFO" 2>&1
  rm -f "$FIFO"
}
