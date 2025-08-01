#!/bin/sh
#
# modules/obsidian-git-client/test.sh — Verify client-side Obsidian Git sync
# Author: deadhedd
# Version: 1.0.0
# Updated: 2025-07-28
#
# Usage: sh test.sh [--log[=FILE]] [--debug[=FILE]] [-h]
#
# Description:
#   Runs TAP-style checks against the local Obsidian vault used for Git-based
#   synchronization. Ensures ssh-agent is loaded, known_hosts has the server,
#   local repo is present, remote bare repo and hooks exist, and that pushing
#   a test commit succeeds.
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

. "$PROJECT_ROOT/config/load-secrets.sh"

BARE_REPO="/home/${GIT_USER}/vaults/${VAULT}.git"
WORK_TREE="/home/${OBS_USER}/vaults/${VAULT}"
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
  echo "1..7"
  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): verifying SSH agent and known hosts" >&2

  run_test "ssh-add -l | grep -q id_ed25519" \
           "ssh-agent running and id_ed25519 loaded" \
           "ssh-add -l"
  run_test "grep -q \"${GIT_SERVER}\" ~/.ssh/known_hosts" \
           "known_hosts contains ${GIT_SERVER}" \
           "grep \"${GIT_SERVER}\" ~/.ssh/known_hosts"


  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): checking local and remote repositories" >&2

  run_test "[ -d \"${LOCAL_VAULT}/.git\" ]" \
           "local vault is a Git repo" \
           "ls -ld \"${LOCAL_VAULT}/.git\""
  run_test "ssh ${GIT_USER}@${GIT_SERVER} [ -d \"${BARE_REPO}\" ]" \
           "remote bare repo exists" \
           "ssh ${GIT_USER}@${GIT_SERVER} ls -ld \"${BARE_REPO}\""
  run_test "ssh ${GIT_USER}@${GIT_SERVER} [ -x \"${BARE_REPO}/hooks/post-receive\" ]" \
           "post-receive hook is present and executable" \
           "ssh ${GIT_USER}@${GIT_SERVER} ls -l \"${BARE_REPO}/hooks/post-receive\""
  run_test "git -C \"${LOCAL_VAULT}\" pull origin" \
           "git pull succeeds over SSH" \
           "git -C \"${LOCAL_VAULT}\" status -s"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): creating and pushing test commit" >&2
  cd "$LOCAL_VAULT" || return 1
  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG: creating test commit in $LOCAL_VAULT" >&2
  echo "# test $(date +%s)" >> test-sync.md
  git add test-sync.md >/dev/null 2>&1
  if [ "$DEBUG_MODE" -eq 1 ]; then
    git commit -m "TDD sync test" >&2

  else
    git commit -m "TDD sync test" >/dev/null 2>&1
  fi
  run_test "git push origin HEAD" \
           "git push succeeds over SSH" \
           "git -C \"${LOCAL_VAULT}\" status -s"
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

