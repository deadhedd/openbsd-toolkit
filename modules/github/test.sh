#!/bin/sh
#
# test.sh — Validate GitHub deploy key & repo bootstrap (github module)
# Usage: $(basename "$0") [--log[=FILE]] [--debug] [-h]
#

##############################################################################
# 1) Resolve paths and load logging helpers
##############################################################################
case "$0" in
  */*) SCRIPT_PATH="$0";;
  *)   SCRIPT_PATH="$PWD/$0";;
esac
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
export PROJECT_ROOT

# shellcheck source=logs/logging.sh
. "$PROJECT_ROOT/logs/logging.sh"

show_help() {
  cat <<-EOF
  Usage: $(basename "$0") [options]

  Description:
    Verify GitHub deploy key and repo bootstrap for Git sync

  Options:
    -h, --help        Show this help message and exit
    -d, --debug       Enable debug mode
    -l, --log         Force log output (use --log=FILE for custom file)
EOF
}

# Check for help
for arg in "$@"; do
  case "$arg" in
    -h|--help) show_help; exit 0 ;;
  esac
done

##############################################################################
# 2) Parse flags and initialize logging
##############################################################################
parse_logging_flags "$@"
eval "set -- $REMAINING_ARGS"

if { [ "$FORCE_LOG" -eq 1 ] || [ "$DEBUG_MODE" -eq 1 ]; } && [ -z "$LOGGING_INITIALIZED" ]; then
  module=$(basename "$SCRIPT_DIR")
  init_logging "${module}-$(basename "$0")"
else
  init_logging "$0"
fi
trap finalize_logging EXIT
[ "$DEBUG_MODE" -eq 1 ] && set -x


##############################################################################
# 4) Load secrets
##############################################################################
# shellcheck source=config/load_secrets.sh
. "$PROJECT_ROOT/config/load_secrets.sh"

##############################################################################
# 5) Default fallbacks (if secrets aren’t set)
##############################################################################
LOCAL_DIR="${LOCAL_DIR:-/root/openbsd-server}"
GITHUB_REPO="${GITHUB_REPO:-git@github.com:deadhedd/openbsd-server.git}"

##############################################################################
# 6) Test helpers
##############################################################################
run_test() {
  desc="$2"
  if eval "$1" >/dev/null 2>&1; then
    echo "ok - $desc"
  else
    echo "not ok - $desc"
    mark_test_failed
  fi
}

##############################################################################
# 7) Define & run tests
##############################################################################
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

##############################################################################
# 8) Exit with status
##############################################################################
if [ "$TEST_FAILED" -ne 0 ]; then
  exit 1
else
  exit 0
fi
