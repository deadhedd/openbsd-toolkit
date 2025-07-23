#!/bin/sh
#
# test.sh — Validate GitHub deploy key & repo bootstrap (github module)
# Usage: $(basename "$0") [--log[=FILE]] [--debug] [-h]
#

# 1) Locate real path & module’s script dir
case "$0" in
  */*) SCRIPT_PATH="$0" ;;
  *)   SCRIPT_PATH="$PWD/$0" ;;
esac
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

# 2) Compute project root (two levels up) & export
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export PROJECT_ROOT

# 3) Source logging helper & parse flags
. "$PROJECT_ROOT/logs/logging.sh"
parse_logging_flags "$@"
eval "set -- $REMAINING_ARGS"

# 4) Turn on xtrace if debugging, else initialize our own log
if [ "$DEBUG_MODE" -eq 1 ] || [ "$FORCE_LOG" -eq 1 ]; then
  set -x
  NEED_FINALIZE=0
else
  init_logging "test-$(basename "$SCRIPT_DIR")"
  NEED_FINALIZE=1
fi

# 5) Handle help
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "Usage: $0 [--log[=FILE]] [--debug] [-h]"
  [ "$NEED_FINALIZE" -eq 1 ] && finalize_logging
  exit 0
fi

# 6) Load secrets
. "$PROJECT_ROOT/config/load_secrets.sh"

# 7) Default fallbacks (if secrets aren’t set)
LOCAL_DIR="${LOCAL_DIR:-/root/openbsd-server}"
GITHUB_REPO="${GITHUB_REPO:-git@github.com:deadhedd/openbsd-server.git}"

# 8) Test helpers
run_test() {
  desc="$2"
  if eval "$1" >/dev/null 2>&1; then
    echo "ok - $desc"
  else
    echo "not ok - $desc"
    mark_test_failed
  fi
}

# 9) Define & run tests
run_tests() {
  echo "1..7"
  run_test "[ -d /root/.ssh ]"                                                  "root .ssh directory exists"
  run_test "[ -f /root/.ssh/id_ed25519 ]"                                        "deploy key present"
  run_test "stat -f '%Lp' /root/.ssh/id_ed25519 | grep -q '^600$'"               "deploy key mode is 600"
  run_test "[ -f /root/.ssh/known_hosts ]"                                       "known_hosts exists"
  run_test "grep -q '^github\\.com ' /root/.ssh/known_hosts"                     "known_hosts contains GitHub"
  run_test "[ -d \"$LOCAL_DIR/.git\" ]"                                          "repository was cloned"
  run_test "grep -q \"url = $GITHUB_REPO\" \"$LOCAL_DIR/.git/config\""           "remote origin set correctly"
}

run_tests

# 10) Finalize logging if we created our own
[ "$NEED_FINALIZE" -eq 1 ] && finalize_logging

# 11) Exit with failure status if any test failed
exit $([ "$TEST_FAILED" -ne 0 ] && echo 1 || echo 0)
