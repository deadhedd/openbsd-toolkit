#!/bin/sh
#
# modules/github/test.sh — Verify GitHub deploy key & repo bootstrap
# Author: deadhedd
# Version: 1.0.0
# Updated: 2025-07-28
#
# Usage: ./test.sh [--log[=FILE]] [--debug] [-h]
#
# Description:
#   Runs TAP-style checks against the GitHub sync setup: verifies that the SSH
#   deploy key and known_hosts entries are present with correct permissions, and
#   that the local repository has been cloned with the expected remote origin.
#
# Deployment considerations:
#   Assumes LOCAL_DIR and GITHUB_REPO are already exported (via
#   config/load-secrets.sh). setup.sh is not required to run this test, but most
#   tests will fail unless it (or equivalent configuration steps) has already
#   been completed.
#
# Security note:
#   Enabling the --debug flag will log all executed commands *and their expanded
#   values* (via `set -vx`), including any exported secrets or credentials.
#   Use caution when sharing or retaining debug logs.
#
# See also:
#   - modules/github/setup.sh
#   - logs/logging.sh
#   - config/load-secrets.sh

##############################################################################
# 0) Resolve paths
##############################################################################

case "$0" in
  */*) SCRIPT_PATH="$0";;
  *)   SCRIPT_PATH="$PWD/$0";;
esac
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
export PROJECT_ROOT

##############################################################################
# 1) Help / banned flags prescan
##############################################################################

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

for arg in "$@"; do
  case "$arg" in
    -h|--help) show_help; exit 0 ;;
  esac
done

##############################################################################
# 2) Parse flags and initialize logging
##############################################################################

# shellcheck source=logs/logging.sh
. "$PROJECT_ROOT/logs/logging.sh"
parse_logging_flags "$@"
eval "set -- $REMAINING_ARGS"

# If running standalone with log/debug requested, include module name in logfile
if { [ "$FORCE_LOG" -eq 1 ] || [ "$DEBUG_MODE" -eq 1 ]; } && [ -z "$LOGGING_INITIALIZED" ]; then
  module_name=$(basename "$SCRIPT_DIR")
  init_logging "${module_name}-$(basename "$0")"
else
  init_logging "$0"
fi
trap finalize_logging EXIT
[ "$DEBUG_MODE" -eq 1 ] && set -vx


##############################################################################
# 3) Load secrets
##############################################################################

# shellcheck source=config/load_secrets.sh
. "$PROJECT_ROOT/config/load_secrets.sh"

##############################################################################
# 4) Test helpers
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
# 5) Define & run tests
##############################################################################
run_tests() {
  echo "1..7"

  # Section 4) SSH setup
  run_test "[ -d /root/.ssh ]"                                                  "root .ssh directory exists"
  run_test "[ -f /root/.ssh/id_ed25519 ]"                                        "deploy key present"
  run_test "stat -f '%Lp' /root/.ssh/id_ed25519 | grep -q '^600$'"               "deploy key mode is 600"
  run_test "[ -f /root/.ssh/known_hosts ]"                                       "known_hosts exists"
  run_test "grep -q '^github\\.com ' /root/.ssh/known_hosts"                     "known_hosts contains GitHub"
  
  # Section 5) Repo bootstrap
  run_test "[ -d \"$LOCAL_DIR/.git\" ]"                                          "repository was cloned"
  run_test "grep -q \"url = $GITHUB_REPO\" \"$LOCAL_DIR/.git/config\""           "remote origin set correctly"
}

run_tests

##############################################################################
# 6) Exit with status
##############################################################################

if [ "$TEST_FAILED" -ne 0 ]; then
  exit 1
else
  exit 0
fi
