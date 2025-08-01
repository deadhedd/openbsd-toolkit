#!/bin/sh
#
# modules/base-system/test.sh — Verify base-system configuration (networking, SSH, history)
# Author: deadhedd
# Version: 1.0.0
# Updated: 2025-07-28
#
# Usage: sh test.sh [--log[=FILE]] [--debug] [-h]
#
# Description:
#   Runs TAP-style checks against the base-system setup: hostname/ifconfig/route,
#   /etc/resolv.conf, SSH hardening, and root shell history settings.
#
# Deployment considerations:
#   Assumes INTERFACE, GIT_SERVER, NETMASK, GATEWAY, DNS1, and DNS2 are already
#   exported (via config/load-secrets.sh). setup.sh is not required to run this
#   test, but most tests will fail unless it (or equivalent configuration steps)
#   has already been completed.
#
# Security note:
#   Enabling the --debug flag will log all executed commands *and their expanded
#   values* (via `set -vx`), including any exported secrets or credentials.
#   Use caution when sharing or retaining debug logs.
#
# See also:
#   - modules/base-system/setup.sh
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
    Validate OpenBSD base system configuration and network setup

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

. "$PROJECT_ROOT/logs/logging.sh"
start_logging "$SCRIPT_PATH" "$@"

##############################################################################
# 3) Load secrets
##############################################################################

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
    echo "# ── Output for failed test: $desc ──"
    echo "$output" | sed 's/^/# /'
    mark_test_failed
  fi
}

assert_file_perm() {
  run_test "stat -f '%Lp' \"$1\" | grep -q '^$2$'" "$3" "stat -f '%Sp' \"$1\""
}

##############################################################################
# 5) Define & run tests
##############################################################################

run_tests() {
  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): starting base-system tests" >&2
  echo "1..15"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 4 networking config files" >&2
  run_test "[ -f /etc/hostname.${INTERFACE} ]"                                "hostname.${INTERFACE} exists" \
           "ls -l /etc/hostname.${INTERFACE}"
  run_test "grep -q \"^inet ${GIT_SERVER} ${NETMASK}$\" /etc/hostname.${INTERFACE}" \
           "correct 'inet IP MASK' line" \
           "grep \"^inet\" /etc/hostname.${INTERFACE}"
  run_test "grep -q \"^!route add default ${GATEWAY}$\" /etc/hostname.${INTERFACE}" \
           "correct default route line" \
           "grep \"^!route add default\" /etc/hostname.${INTERFACE}"

  run_test "[ -f /etc/resolv.conf ]"                                          "resolv.conf exists" \
           "ls -l /etc/resolv.conf"
  run_test "grep -q \"nameserver ${DNS1}\" /etc/resolv.conf"                  "resolv.conf contains DNS1" \
           "grep 'nameserver' /etc/resolv.conf"
  run_test "grep -q \"nameserver ${DNS2}\" /etc/resolv.conf"                  "resolv.conf contains DNS2" \
           "grep 'nameserver' /etc/resolv.conf"
  assert_file_perm "/etc/resolv.conf" "644"                                   "resolv.conf mode is 644"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 5 apply networking" >&2
  run_test "ifconfig ${INTERFACE} | grep -q \"inet ${GIT_SERVER}\""            "interface up with correct IP" \
           "ifconfig ${INTERFACE}"
  run_test "netstat -rn | grep -q '^default[[:space:]]*${GATEWAY}'"            "default route via ${GATEWAY}" \
           "netstat -rn"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 6 SSH hardening" >&2
  run_test "grep -q '^PermitRootLogin no' /etc/ssh/sshd_config"               "sshd_config disallows root login" \
           "grep '^PermitRootLogin' /etc/ssh/sshd_config"
  run_test "grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config"        "sshd_config disallows password auth" \
           "grep '^PasswordAuthentication' /etc/ssh/sshd_config"
  run_test "rcctl check sshd"                                                  "sshd service is running" \
           "ps -ax | grep '[s]shd'"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 7 root history" >&2
  run_test "grep -q '^export HISTFILE=/root/.ksh_history' /root/.profile"      "root .profile sets HISTFILE" \
           "grep '^export HISTFILE' /root/.profile"
  run_test "grep -q '^export HISTSIZE=5000' /root/.profile"                    "root .profile sets HISTSIZE" \
           "grep '^export HISTSIZE' /root/.profile"
  run_test "grep -q '^export HISTCONTROL=ignoredups' /root/.profile"           "root .profile sets HISTCONTROL" \
           "grep '^export HISTCONTROL' /root/.profile"
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
