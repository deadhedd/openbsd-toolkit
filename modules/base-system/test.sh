#!/bin/sh
#
# test.sh - Verify general system configuration for base-system module
# Usage: ./test.sh [--log[=FILE]] [--debug] [-h]
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

. "$PROJECT_ROOT/logs/logging.sh"

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

# If running standalone with log/debug requested, include module name in logfile
if { [ "$FORCE_LOG" -eq 1 ] || [ "$DEBUG_MODE" -eq 1 ]; } && [ -z "$LOGGING_INITIALIZED" ]; then
  module_name=$(basename "$SCRIPT_DIR")
  init_logging "${module_name}-$(basename "$0")"
else
  init_logging "$0"
fi
trap finalize_logging EXIT
[ "$DEBUG_MODE" -eq 1 ] && set -x



##############################################################################
# 4) Load configuration
##############################################################################
. "$PROJECT_ROOT/config/load_secrets.sh"

##############################################################################
# 5) Test helpers
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
assert_file_perm() {
  run_test "stat -f '%Lp' \"$1\" | grep -q '^$2$'" "$3"
}

##############################################################################
# 6) Define & run tests
##############################################################################
run_tests() {
  echo "1..15"
  run_test "[ -f /etc/hostname.${INTERFACE} ]"                                "hostname.${INTERFACE} exists"
  run_test "grep -q \"^inet ${GIT_SERVER} ${NETMASK}$\" /etc/hostname.${INTERFACE}" \
           "correct 'inet IP MASK' line"
  run_test "grep -q \"^!route add default ${GATEWAY}$\" /etc/hostname.${INTERFACE}" \
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

run_tests

##############################################################################
# 7) Exit with status
##############################################################################
if [ "$TEST_FAILED" -ne 0 ]; then
  exit 1
else
  exit 0
fi
