#!/bin/sh
#
# test_github.sh – Verify GitHub SSH key & repo bootstrap (with optional logging)
# Usage: ./test_github.sh [--log[=FILE]] [-h]
#

set -ex  # -e: exit on error; -x: trace commands

#
# 1) Locate this script’s real path
#
case "$0" in
  */*) SCRIPT_PATH="$0" ;;
  *)   SCRIPT_PATH="$(command -v -- "$0" 2>/dev/null || printf "%s" "$0")" ;;
esac
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"

#
# 2) Logging defaults
#
FORCE_LOG=0
LOGFILE=""

#
# 3) Usage helper
#
usage() {
  cat <<EOF
Usage: $(basename "$0") [--log[=FILE]] [-h]

  --log, -l       Capture stdout, stderr & xtrace into:
                   \${PROJECT_ROOT}/logs/$(basename "$0" .sh)-TIMESTAMP.log
                 Or use --log=FILE to choose a custom path.

  -h, --help      Show this help and exit.
EOF
  exit 0
}

#
# 4) Parse flags
#
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

#
# 5) Centralized logging init (handle tests/ or scripts/ subdir)
#
base="$(basename "$SCRIPT_DIR")"
if [ "$base" = "tests" ] || [ "$base" = "scripts" ]; then
  PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
else
  PROJECT_ROOT="$SCRIPT_DIR"
fi

LOG_HELPER="$PROJECT_ROOT/logs/logging.sh"
[ -f "$LOG_HELPER" ] || { echo "❌ logging.sh not found at $LOG_HELPER" >&2; exit 1; }
. "$LOG_HELPER"
init_logging "$0"

#
# 6) Load secrets
#
. "$PROJECT_ROOT/config/load_secrets.sh"

#
# 7) Test-framework definitions
#
run_test() {
  desc="$2"
  if eval "$1" >/dev/null 2>&1; then
    echo "ok - $desc"
  else
    echo "not ok - $desc"
    return 1
  fi
}

assert_file_perm() {
  path="$1"; want="$2"; desc="$3"
  run_test "stat -f '%Lp' \"$path\" | grep -q '^$want\$'" "$desc"
}

#
# 8) Actual tests
#
run_tests() {
  local_dir=${LOCAL_DIR:-/root/openbsd-server}
  github_repo=${GITHUB_REPO:-git@github.com:deadhedd/openbsd-server.git}

  echo "1..7"
  run_test "[ -d /root/.ssh ]"                                          "root .ssh directory exists"
  run_test "[ -f /root/.ssh/id_ed25519 ]"                               "deploy key present"
  assert_file_perm "/root/.ssh/id_ed25519" "600"                        "deploy key mode is 600"

  run_test "[ -f /root/.ssh/known_hosts ]"                              "root known_hosts exists"
  run_test "grep -q '^github\\.com ' /root/.ssh/known_hosts"            "known_hosts contains github.com"

  run_test "[ -d \"\$local_dir/.git\" ]"                                "repository cloned into \$local_dir"
  run_test "grep -q \"url = \$github_repo\" \"\$local_dir/.git/config\"" "remote origin set to GITHUB_REPO"
}

#
# 9) Wrapper to capture output and optionally log
#
run_and_maybe_log() {
  TMP="$(mktemp)" || exit 1

  if ! run_tests >"$TMP" 2>&1; then
    echo "🛑 $(basename "$0") FAILED — dumping full log to $LOGFILE"
    cat "$TMP" | tee "$LOGFILE"
    rm -f "$TMP"
    exit 1
  else
    if [ "$FORCE_LOG" -eq 1 ]; then
      echo "✅ $(basename "$0") passed — writing full log to $LOGFILE"
      cat "$TMP" >>"$LOGFILE"
    else
      cat "$TMP"
    fi
    rm -f "$TMP"
  fi
}

#
# 10) Execute
#
run_and_maybe_log

