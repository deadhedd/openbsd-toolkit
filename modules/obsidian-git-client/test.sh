#!/bin/sh
#
# modules/obsidian-git-client/test.sh — Verify client-side Obsidian Git sync
# Author: deadhedd
# Version: 1.0.1
# Updated: 2025-08-02
#
# Usage: sh test.sh [--log[=FILE]] [--debug[=FILE]] [-h]
#
# Description:
#   Runs a minimal check against the local Obsidian vault used for Git-based
#   synchronization. Verifies the vault is a Git repository.
#
# Security note:
#   Enabling the --debug flag will log all executed commands (via `set -x`).
#   Setup scripts still log expanded values via `set -vx`, which may include
#   exported secrets or credentials. Use caution when sharing or retaining
#   debug logs.

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
  cat <<EOF
  Usage: sh $(basename "$0") [options]

  Description:
    Validate client-side Obsidian Git sync configuration

  Options:
    -h, --help        Show this help message and exit
    -d, --debug       Enable debug mode (use --debug=FILE for custom file)
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

. "$PROJECT_ROOT/logs/logging.sh"
start_logging "$SCRIPT_PATH" "$@"

##############################################################################
# 3) Load secrets
##############################################################################

. "$PROJECT_ROOT/config/load-secrets.sh" "Base System"
. "$PROJECT_ROOT/config/load-secrets.sh" "Obsidian Git Host"

LOCAL_VAULT="$HOME/${VAULT}"

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

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): starting obsidian-git-client tests" >&2
  echo "1..1"

  run_test "[ -d \"${LOCAL_VAULT}/.git\" ]" \
           "local vault is a Git repo" \
           "ls -ld \"${LOCAL_VAULT}/.git\""
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

