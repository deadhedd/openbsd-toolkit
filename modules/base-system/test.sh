#!/bin/sh
#
# modules/base-system/test.sh — Verify base-system configuration (networking, SSH, history)
# Author: deadhedd
# Version: 1.0.0
# Updated: 2025-07-28
#
# Usage: ./test.sh [--log[=FILE]] [--debug] [-h]
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
  Usage: $(basename "$0") [options]

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

echo "stdout: hello world"
echo "stderr: uh oh" >&2

run_test() {
  desc="$2"
  output="$(eval "$1" 2>&1)"
  if [ $? -eq 0 ]; then
    echo "ok - $desc"
  else
    echo "not ok - $desc"
    echo "# ── Output for failed test: $desc ──"
    echo "$output" | sed 's/^/# /'
    mark_test_failed
  fi
}

assert_file_perm() {
  run_test "stat -f '%Lp' \"$1\" | grep -q '^$2$'" "$3"
}

##############################################################################
# 5) Define & run tests
##############################################################################

run_tests() {
  echo "1..15"

  # Section 4) Networking config files
  run_test "[ -f /etc/hostname.${INTERFACE} ]"                                "hostname.${INTERFACE} exists"
  run_test "grep -q \"^inet ${GIT_SERVER} ${NETMASK}$\" /etc/hostname.${INTERFACE}" \
           "correct 'inet IP MASK' line"
  run_test "grep -q \"^!route add default ${GATEWAY}$\" /etc/hostname.${INTERFACE}" \
           "correct default route line"

  run_test "[ -f /etc/resolv.conf ]"                                          "resolv.conf exists"
  run_test "grep -q \"nameserver ${DNS1}\" /etc/resolv.conf"                  "resolv.conf contains DNS1"
  run_test "grep -q \"nameserver ${DNS2}\" /etc/resolv.conf"                  "resolv.conf contains DNS2"
  assert_file_perm "/etc/resolv.conf" "644"                                   "resolv.conf mode is 644"

  # Section 5) Apply Networking
  run_test "ifconfig ${INTERFACE} | grep -q \"inet ${GIT_SERVER}\""            "interface up with correct IP"
  run_test "netstat -rn | grep -q '^default[[:space:]]*${GATEWAY}'"            "default route via ${GATEWAY}"
  
  # Section 6) SSH hardening
  run_test "grep -q '^PermitRootLogin no' /etc/ssh/sshd_config"               "sshd_config disallows root login"
  run_test "grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config"        "sshd_config disallows password auth"
  run_test "rcctl check sshd"                                                  "sshd service is running"

  # Section 7) Root history
  run_test "grep -q '^export HISTFILE=/root/.ksh_history' /root/.profile"      "root .profile sets HISTFILE"
  run_test "grep -q '^export HISTSIZE=5000' /root/.profile"                    "root .profile sets HISTSIZE"
  run_test "grep -q '^export HISTCONTROL=ignoredups' /root/.profile"           "root .profile sets HISTCONTROL"
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
