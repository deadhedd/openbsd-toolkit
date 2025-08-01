#!/bin/sh
#
# modules/github/test.sh — Verify GitHub deploy key & repo bootstrap
# Author: deadhedd
# Version: 1.0.0
# Updated: 2025-07-28
#
# Usage: sh test.sh [--log[=FILE]] [--debug] [-h]
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
#   Enabling the --debug flag will log all executed commands (via `set -x`).
#   Setup scripts still log expanded values via `set -vx`, which may include
#   exported secrets or credentials. Use caution when sharing or retaining
#   debug logs.
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
  Usage: sh $(basename "$0") [options]

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
start_logging "$SCRIPT_PATH" "$@"


##############################################################################
# 3) Load secrets
##############################################################################

# shellcheck source=config/load_secrets.sh
. "$PROJECT_ROOT/config/load_secrets.sh"

##############################################################################
# 4) Test helpers
##############################################################################

run_test() {
  cmd="$1"
  desc="$2"
  inspect="$3"
  if [ "$DEBUG_MODE" -eq 1 ]; then
    echo "DEBUG(run_test): $desc -> $cmd" >&2
    if [ -n "$inspect" ]; then
      inspect_out="$(eval "$inspect" 2>&1 || true)"
      [ -n "$inspect_out" ] && printf '%s\n' "DEBUG(run_test): inspect ->\n$inspect_out" >&2
    fi
  fi
  output="$(eval "$cmd" 2>&1)"
  status=$?
  if [ "$DEBUG_MODE" -eq 1 ]; then
    echo "DEBUG(run_test): exit_status=$status" >&2
    [ -n "$output" ] && printf '%s\n' "DEBUG(run_test): output ->\n$output" >&2
  fi
  if [ $status -eq 0 ]; then
    echo "ok - $desc"
  else
    echo "not ok - $desc"
    [ -n "$output" ] && {
      echo "# ── Output for failed test: $desc ──"
      echo "$output" | sed 's/^/# /'
    }
    mark_test_failed
  fi
}

##############################################################################
# 5) Define & run tests
##############################################################################
run_tests() {

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): starting github tests" >&2
  echo "1..7"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 4 SSH setup" >&2
  run_test "[ -d /root/.ssh ]"                                                  "root .ssh directory exists" \
           "ls -ld /root/.ssh"
  run_test "[ -f /root/.ssh/id_ed25519 ]"                                        "deploy key present" \
           "ls -l /root/.ssh/id_ed25519"
  run_test "stat -f '%Lp' /root/.ssh/id_ed25519 | grep -q '^600$'"               "deploy key mode is 600" \
           "stat -f '%Sp' /root/.ssh/id_ed25519"
  run_test "[ -f /root/.ssh/known_hosts ]"                                       "known_hosts exists" \
           "ls -l /root/.ssh/known_hosts"
  run_test "grep -q '^github\\.com ' /root/.ssh/known_hosts"                     "known_hosts contains GitHub" \
           "grep '^github\\.com' /root/.ssh/known_hosts"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 5 repo bootstrap" >&2

  run_test "[ -d \"$LOCAL_DIR/.git\" ]"                                          "repository was cloned" \
           "ls -ld \"$LOCAL_DIR/.git\""
  run_test "grep -q \"url = $GITHUB_REPO\" \"$LOCAL_DIR/.git/config\""           "remote origin set correctly" \
           "grep 'url =' \"$LOCAL_DIR/.git/config\""
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
