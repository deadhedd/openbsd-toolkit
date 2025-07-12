#!/bin/sh
#
# test_system.sh – Verify general system configuration for Obsidian-Git-Host setup (with optional logging)
# Usage: ./test_system.sh [--log[=FILE]] [-h]
#

set -e

# 1) Locate this script’s directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 2) Logging defaults
FORCE_LOG=0
LOGFILE=""

# 3) Usage helper
usage() {
  cat <<EOF
Usage: $(basename "$0") [--log[=FILE]] [-h]

  --log, -l       Capture stdout, stderr, and xtrace into:
                    \${SCRIPT_DIR}/../logs/$(basename "$0" .sh)-TIMESTAMP.log
                  Or use --log=FILE to choose a custom path.

  -h, --help      Show this help and exit.
EOF
  exit 0
}

# 4) Parse flags
while [ $# -gt 0 ]; do
  case "$1" in
    -l|--log)
      FORCE_LOG=1
      ;;
    -l=*|--log=*)
      FORCE_LOG=1
      LOGFILE="${1#*=}"
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
  shift
done

# 5) Centralized logging init
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$PROJECT_ROOT/logs/logging.sh"
init_logging "$0"

# 6) (Optional) enable xtrace for detailed logs
# set -x

# 7) Load secrets
. "$PROJECT_ROOT/config/load_secrets.sh"

# 8) Run tests in a function to capture output
run_tests() {
  tests=0; fails=0

  run_test() {
    tests=$((tests+1))
    desc="$2"
    if eval "$1" >/dev/null 2>&1; then
      echo "ok $tests - $desc"
    else
      echo "not ok $tests - $desc"
      fails=$((fails+1))
    fi
  }

  assert_file_perm() {
    path=$1; want=$2; desc=$3
    run_test "stat -f '%Lp' $path | grep -q '^$want\$'" "$desc"
  }

  echo "1..15"

  # 1–3: Interface config
  run_test "[ -f /etc/hostname.${INTERFACE} ]"                                             "hostname.${INTERFACE} exists"
  run_test "grep -q \"^inet ${STATIC_IP} ${NETMASK}\$\" /etc/hostname.${INTERFACE}"       "correct IP/MASK in hostname.${INTERFACE}"
  run_test "grep -q \"^!route add default ${GATEWAY}\$\" /etc/hostname.${INTERFACE}"       "correct default route in hostname.${INTERFACE}"

  # 4–7: DNS & resolv.conf
  run_test "[ -f /etc/resolv.conf ]"                                                      "resolv.conf exists"
  run_test "grep -q \"nameserver ${DNS1}\" /etc/resolv.conf"                              "resolv.conf contains ${DNS1}"
  run_test "grep -q \"nameserver ${DNS2}\" /etc/resolv.conf"                              "resolv.conf contains ${DNS2}"
  assert_file_perm "/etc/resolv.conf" "644"                                               "resolv.conf permissions"

  # 8–9: Interface up & route
  run_test "ifconfig ${INTERFACE} | grep -q \"inet ${STATIC_IP}\""                        "interface ${INTERFACE} up with IP ${STATIC_IP}"
  run_test "netstat -rn | grep -q '^default[[:space:]]*${GATEWAY}'"                         "default route via ${GATEWAY}"

  # 10–12: SSH hardening
  run_test "grep -q '^PermitRootLogin no' /etc/ssh/sshd_config"                            "sshd_config: PermitRootLogin no"
  run_test "grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config"                     "sshd_config: PasswordAuthentication no"
  run_test "rcctl check sshd"                                                              "sshd service is running"

  # 13–15: Root history settings
  run_test "grep -q '^export HISTFILE=/root/.ksh_history' /root/.profile"                  "root .profile sets HISTFILE"
  run_test "grep -q '^export HISTSIZE=5000' /root/.profile"                                "root .profile sets HISTSIZE"
  run_test "grep -q '^export HISTCONTROL=ignoredups' /root/.profile"                       "root .profile sets HISTCONTROL"

  echo ""
  if [ "$fails" -eq 0 ]; then
    echo "✅ All $tests tests passed."
  else
    echo "❌ $fails of $tests tests failed."
  fi

  return $fails
}

# 9) Wrapper to capture output and optionally log
run_and_maybe_log() {
  TMP="$(mktemp)" || exit 1

  if ! run_tests >"$TMP" 2>&1; then
    echo "🛑 $(basename "$0") FAILED — dumping full log to $LOGFILE"
    cat "$TMP" | tee "$LOGFILE"
    rm -f "$TMP"
    exit 1
  else
    if [ "$FORCE_LOG" -eq 1 ]; then
      echo "✅ $(basename "$0") passed — writing full log to $LOGFILE"
      cat "$TMP" >>"$LOGFILE"
    else
      cat "$TMP"
    fi
    rm -f "$TMP"
  fi
}

# 10) Execute
run_and_maybe_log

