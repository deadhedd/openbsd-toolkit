#!/bin/sh
#
# test.sh — Verify general system configuration for base-system module (with optional logging)
# Usage: ./test.sh [--log[=FILE]] [--debug[=FILE]] [-h]

# 1) Locate this script’s real path
case "$0" in
  */*) SCRIPT_PATH="$0"   ;;
  *)   SCRIPT_PATH="$(command -v -- "$0" 2>/dev/null || printf "%s" "$0")" ;;
esac
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"

# 2) Determine project root (two levels up from module)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 3) Logging flags
FORCE_LOG=0
DEBUG_LOG=0
LOGFILE=""

# 4) Usage helper
usage() {
  cat <<-EOF
Usage: $(basename "$0") [--log[=FILE]] [--debug[=FILE]] [-h]

  -l, --log        capture stdout+stderr in a central log
  -l=FILE          write central log to FILE
  -d, --debug      as --log, plus trace every command
  -d=FILE          debug central log to FILE
  -h, --help       Show this help and exit.
EOF
  exit 0
}

# 5) Parse flags
while [ $# -gt 0 ]; do
  case "$1" in
    -l|--log)
      FORCE_LOG=1
      shift
      ;;
    -l=*|--log=*)
      FORCE_LOG=1
      LOGFILE="${1#*=}"
      shift
      ;;
    -d|--debug)
      DEBUG_LOG=1
      FORCE_LOG=1
      shift
      ;;
    -d=*|--debug=*)
      DEBUG_LOG=1
      FORCE_LOG=1
      LOGFILE="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

# 6) Centralized logging init
LOG_HELPER="$PROJECT_ROOT/logs/logging.sh"
[ -f "$LOG_HELPER" ] || { echo "❌ logging.sh not found at $LOG_HELPER" >&2; exit 1; }
# pass $0 so the helper can name the log after this script
. "$LOG_HELPER" "$0"

# 7) Load secrets
. "$PROJECT_ROOT/config/load_secrets.sh"

# 8) Test framework
run_test() {
  desc="$2"
  if eval "$1" >/dev/null 2>&1; then
    echo "ok - $desc"
  else
    echo "not ok - $desc"
    return 1
  fi
}

assert_file_perm() {
  path="$1"; want="$2"; desc="$3"
  run_test "stat -f '%Lp' \"$path\" | grep -q '^$want\$'" "$desc"
}

# 9) Define and run tests
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

# 10) Execute all tests
run_tests
