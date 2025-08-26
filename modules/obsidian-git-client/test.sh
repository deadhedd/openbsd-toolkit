#!/bin/sh
#
# modules/obsidian-git-client/test.sh — Verify client-side Obsidian Git sync
# Author: deadhedd
# Version: 1.0.2
# Updated: 2025-08-22
#
# Usage: sh test.sh [--log[=FILE]] [--debug[=FILE]] [-h]
#
# Description:
#   Runs TAP-style checks against the local Obsidian vault used for Git-based
#   synchronization. Ensures ssh-agent is loaded, known_hosts has the server,
#   the local repo is present, and the remote origin is configured.
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
. "$PROJECT_ROOT/config/load-secrets.sh" "Obsidian Git Client"

LOCAL_VAULT="$HOME/${CLIENT_VAULT}"
SSH_KEY_FILE="${CLIENT_SSH_KEY_PATH:-$HOME/.ssh/id_ed25519}"
SSH_KEY_BASENAME="$(basename "$SSH_KEY_FILE")"

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
  echo "1..12"
  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): verifying Obsidian plugin installation" >&2

  run_test "[ -d \"${LOCAL_VAULT}/.obsidian/plugins/obsidian-git\" ]" \
           "obsidian-git plugin directory exists" \
           "ls -ld \"${LOCAL_VAULT}/.obsidian/plugins/obsidian-git\""
  run_test "grep -q 'obsidian-git' \"${LOCAL_VAULT}/.obsidian/plugins.json\"" \
           "obsidian-git listed in vault/.obsidian/plugins.json" \
           "grep 'obsidian-git' \"${LOCAL_VAULT}/.obsidian/plugins.json\""

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): verifying auto-sync settings" >&2

  run_test "grep -q \"Repository path.*${LOCAL_VAULT}\" \"${LOCAL_VAULT}/.obsidian/plugins/obsidian-git.json\"" \
           "Obsidian Git repo path points at ${LOCAL_VAULT}" \
           "grep 'Repository path' \"${LOCAL_VAULT}/.obsidian/plugins/obsidian-git.json\""
  run_test "grep -q 'autoCommit.*true' \"${LOCAL_VAULT}/.obsidian/plugins/obsidian-git.json\"" \
           "auto-commit on file change enabled" \
           "grep 'autoCommit' \"${LOCAL_VAULT}/.obsidian/plugins/obsidian-git.json\""
  run_test "grep -q 'autoPushInterval.*[1-9]' \"${LOCAL_VAULT}/.obsidian/plugins/obsidian-git.json\"" \
           "auto-push interval configured" \
           "grep 'autoPushInterval' \"${LOCAL_VAULT}/.obsidian/plugins/obsidian-git.json\""
  run_test "grep -q 'pullBeforePush.*true' \"${LOCAL_VAULT}/.obsidian/plugins/obsidian-git.json\"" \
           "pull-before-push enabled" \
           "grep 'pullBeforePush' \"${LOCAL_VAULT}/.obsidian/plugins/obsidian-git.json\""

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): verifying SSH agent and known hosts" >&2

  run_test ". \"$HOME/.ssh/agent.env\" 2>/dev/null; ssh-add -l | grep -q \"$SSH_KEY_BASENAME\"" \
           "ssh-agent running and $SSH_KEY_BASENAME loaded" \
           ". \"$HOME/.ssh/agent.env\" 2>/dev/null; ssh-add -l"
  run_test "grep -q \"${GIT_SERVER}\" ~/.ssh/known_hosts" \
           "known_hosts contains ${GIT_SERVER}" \
           "grep \"${GIT_SERVER}\" ~/.ssh/known_hosts"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): checking local repository configuration" >&2

  run_test "[ -d \"${LOCAL_VAULT}/.git\" ]" \
           "local vault is a Git repo" \
           "ls -ld \"${LOCAL_VAULT}/.git\""
  run_test "git -C \"${LOCAL_VAULT}\" remote get-url origin | grep -q \"${GIT_SERVER}:/home/${GIT_USER}/vaults/${VAULT}.git\"" \
           "git remote 'origin' correctly set" \
           "git -C \"${LOCAL_VAULT}\" remote -v"
  run_test "git -C \"${LOCAL_VAULT}\" config --get push.default | grep -q '^current$'" \
           "git push.default is set to 'current'" \
           "git -C \"${LOCAL_VAULT}\" config --get push.default"
  run_test "git -C \"${LOCAL_VAULT}\" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1" \
           "current branch tracks an upstream" \
           "git -C \"${LOCAL_VAULT}\" rev-parse --abbrev-ref --symbolic-full-name '@{u}'"
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
