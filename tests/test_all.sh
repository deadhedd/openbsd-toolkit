#!/bin/sh
#
# test_all.sh – Run the full suite of tests, with optional logging.
#

# 1) Figure out where this script lives, so we can reliably call its siblings
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

# 2) Where to dump logs by default
LOGDIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOGDIR"

# 3) Defaults: only write a log on failure unless --log is passed
FORCE_LOG=0
LOGFILE=""

# 4) Usage helper
usage() {
  cat <<EOF
Usage: $0 [--log[=FILE]] [-h]

  --log[=FILE]   Always write full output to FILE.
                 If you omit '=FILE', defaults to:
                   $LOGDIR/test_all-YYYYMMDD_HHMMSS.log

  -h, --help     Show this help and exit.
EOF
  exit 1
}

# 5) Parse command‑line flags
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
      usage
      ;;
  esac
  shift
done

# 6) If no explicit logfile was given, pick a timestamped default
if [ -z "$LOGFILE" ]; then
  LOGFILE="${LOGDIR}/test_all-$(date '+%Y%m%d_%H%M%S').log"
fi

# 7) Make sure each test script exists (we’ll invoke them via `sh`)
SCRIPTS="
  test_system.sh
  test_obsidian_git.sh
  test_github.sh
"
for script in $SCRIPTS; do
  if [ ! -f "${SCRIPT_DIR}/${script}" ]; then
    echo "Error: ${script} not found in ${SCRIPT_DIR}" >&2
    exit 1
  fi
done

# 8) Run them all, buffer output, and decide whether to log
run_and_maybe_log() {
  TMP="$(mktemp)" || exit 1

  if ! {
       sh "${SCRIPT_DIR}/test_system.sh"       && \
       sh "${SCRIPT_DIR}/test_obsidian_git.sh" && \
       sh "${SCRIPT_DIR}/test_github.sh"
     } >"$TMP" 2>&1; then

    echo "🛑 Some tests FAILED — dumping full log to $LOGFILE"
    cat "$TMP" | tee "$LOGFILE"
    rm -f "$TMP"
    exit 1
  else
    if [ "$FORCE_LOG" -eq 1 ]; then
      echo "ℹ️  Tests passed — writing full log to $LOGFILE"
      cat "$TMP" >>"$LOGFILE"
    else
      cat "$TMP"
    fi
    rm -f "$TMP"
  fi
}

# 9) Execute the suite
run_and_maybe_log
echo "✅ All tests passed."
