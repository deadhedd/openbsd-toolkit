#!/bin/sh
#
# test.sh — Verify general system configuration for base-system module
# Usage: ./test.sh [--log[=FILE]] [--debug] [-h]
#

# 1) Locate this script’s real path
case "$0" in
  */*) SCRIPT_PATH="$0"   ;;
  *)   SCRIPT_PATH="$PWD/$0"   ;;   # assume cwd if no slash
esac
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

# 2) Determine project root (two levels up from module dir)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export PROJECT_ROOT

# 3) Source our logging framework, strip flags, init logging
. "$PROJECT_ROOT/logs/logging.sh"
set -- $(parse_logging_flags "$@")   # now $@ = any non-logging args (e.g. -h)
init_logging "test-base-system"

# 4) Handle help request
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "Usage: $0 [--log[=FILE]] [--debug] [-h]"
  finalize_logging
  exit 0
fi

# 5) Load secrets needed by the tests
. "$PROJECT_ROOT/config/load_secrets.sh"

# 6) Test framework
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
  path="$1"; want="$2"; desc="$3"
  run_test "stat -f '%Lp' \"$path\" | grep -q '^$want\$'" "$desc"
}

# 7) Define & run tests
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

# 8) Execute
run_tests

# 9) Finalize and exit
finalize_logging
[ "$TEST_FAILED" -ne 0 ] && exit 1 || exit 0
