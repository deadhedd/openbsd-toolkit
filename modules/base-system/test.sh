#!/bin/sh
#
# test.sh — Verify general system configuration for base-system module
# Usage: ./test.sh [--log[=FILE]] [--debug] [-h]
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
. "$PROJECT_ROOT/scripts/logging.sh"
set -- $(parse_logging_flags "$@")   # strips out --log/--debug

# 4) Decide if we should init our own log
if [ "$FORCE_LOG" -eq 1 ] || [ "$DEBUG_MODE" -eq 1 ]; then
  init_logging "test-base-system"
  NEED_FINALIZE=1
else
  NEED_FINALIZE=0
fi

# 5) Handle help
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "Usage: $0 [--log[=FILE]] [--debug] [-h]"
  [ "$NEED_FINALIZE" -eq 1 ] && finalize_logging
  exit 0
fi

# 6) Load secrets
. "$PROJECT_ROOT/config/load_secrets.sh"

# 7) Test helpers
run_test() {
  desc="$2"
  if eval "$1" >/dev/null 2>&1; then
    echo "ok - $desc"
  else
    echo "not ok - $desc"
    mark_test_failed
  fi
}
assert_file_perm() {
  run_test "stat -f '%Lp' \"$1\" | grep -q '^$2\$'" "$3"
}

# 8) Define & run tests
run_tests() {
  echo "1..15"
  run_test "[ -f /etc/hostname.${INTERFACE} ]"                                "hostname.${INTERFACE} exists"
  run_test "grep -q \"^inet ${GIT_SERVER} ${NETMASK}\$\" /etc/hostname.${INTERFACE}" \
           "correct 'inet IP MASK' line"
  run_test "grep -q \"^!route add default ${GATEWAY}\$\" /etc/hostname.${INTERFACE}" \
           "correct default route line"
  run_test "[ -f /etc/resolv.conf ]"                                          "resolv.conf exists"
  run_test "grep -q \"nameserver ${DNS1}\" /etc/resolv.conf"                  "resolv.conf contains DNS1"
  run_test "grep -q \"nameserver ${DNS2}\" /etc/resolv.conf"                  "resolv.conf contains DNS2"
  assert_file_perm "/etc/resolv.conf" "644"                                   "resolv.conf mode is 644"
  run_test "ifconfig ${INTERFACE} | grep -q \"inet ${GIT_SERVER}\""            "interface up with correct IP"
  run_test "netstat -rn | grep -q '^default[[:space:]]*${GATEWAY}'"            "default route via ${GATEWAY}"
  run_test "grep -q '^PermitRootLogin no' /etc/ssh/sshd_config"               "sshd_config disallows root login"
  run_test "grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config"        "sshd_config disallows password auth"
  run_test "rcctl check sshd"                                                  "sshd service is running"
  run_test "grep -q '^export HISTFILE=/root/.ksh_history' /root/.profile"      "root .profile sets HISTFILE"
  run_test "grep -q '^export HISTSIZE=5000' /root/.profile"                    "root .profile sets HISTSIZE"
  run_test "grep -q '^export HISTCONTROL=ignoredups' /root/.profile"           "root .profile sets HISTCONTROL"
}

# 9) Execute tests
run_tests

# 10) Finalize logging if we created our own
if [ "$NEED_FINALIZE" -eq 1 ]; then
  finalize_logging
fi

exit [ "$TEST_FAILED" -ne 0 ] && 1 || 0
