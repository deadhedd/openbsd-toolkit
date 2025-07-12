#!/bin/sh
#
# test_all.sh – Run the full suite of tests, with optional centralized logging.
# Usage: ./test_all.sh [--log[=FILE]] [-h]
#

set -X

# 1) Locate this script’s directory
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

# 2) Logging defaults
FORCE_LOG=0
LOGFILE=""

# 3) Usage helper
usage() {
  cat <<EOF
Usage: $0 [--log[=FILE]] [-h]

  --log, -l         Capture stdout, stderr, and any xtrace into a log
                    under ${SCRIPT_DIR}/logs/.
                    Use --log=FILE to specify a custom path.

  -h, --help        Show this help and exit.
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
      usage
      ;;
  esac
  shift
done

# 5) Centralized logging init
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
if     [ -f "$SCRIPT_DIR/logs/logging.sh" ]; then
  LOG_HELPER="$SCRIPT_DIR/logs/logging.sh"
elif   [ -f "$SCRIPT_DIR/../logs/logging.sh" ]; then
  LOG_HELPER="$SCRIPT_DIR/../logs/logging.sh"
else
  echo "❌ logging.sh not found in logs/ or ../logs/" >&2
  exit 1
fi

. "$LOG_HELPER"
init_logging "$0"

# 6) Turn on xtrace so everything shows up in the log
set -x

# 7) Run the three setup scripts
echo "👉 Running system setup…"
sh "$SCRIPT_DIR/scripts/setup_system.sh"

echo "👉 Running Obsidian-git setup…"
sh "$SCRIPT_DIR/scripts/setup_obsidian_git.sh"

echo "👉 Running GitHub setup…"
sh "$SCRIPT_DIR/scripts/setup_github.sh"

echo ""
echo "✅ All setup scripts completed successfully."


# 6) (Optional) enable xtrace to include in the log
# set -x

# 7) Ensure each test script exists
for script in test_system.sh test_obsidian_git.sh test_github.sh; do
  if [ ! -f "${SCRIPT_DIR}/${script}" ]; then
    echo "Error: ${script} not found in ${SCRIPT_DIR}" >&2
    exit 1
  fi
done

# 8) Run tests, buffer their output for concise console display
run_and_maybe_log() {
  TMP="$(mktemp)" || exit 1
  fail=0

  for script in \
      "${SCRIPT_DIR}/test_system.sh" \
      "${SCRIPT_DIR}/test_obsidian_git.sh" \
      "${SCRIPT_DIR}/test_github.sh"; do

    printf "⏳ Running %s …\n" "$(basename "$script")" >>"$TMP"
    if ! sh "$script" >>"$TMP" 2>&1; then
      printf "🛑 %s FAILED\n\n" "$(basename "$script")" >>"$TMP"
      fail=1
    else
      printf "✅ %s passed\n\n" "$(basename "$script")" >>"$TMP"
    fi
  done

  if [ "$fail" -ne 0 ]; then
    echo "🛑 Some tests FAILED — see full log in $LOGFILE"
    cat "$TMP"
    rm -f "$TMP"
    exit 1
  else
    if [ "$FORCE_LOG" -eq 1 ]; then
      echo "ℹ️  Tests passed — full log in $LOGFILE"
    fi
    cat "$TMP"
    rm -f "$TMP"
    echo "✅ All tests passed."
  fi
}

# 9) Execute the suite
run_and_maybe_log

