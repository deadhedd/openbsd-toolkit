#!/bin/sh
#
# test_system.sh – Verify general system configuration for Obsidian‑Git‑Host setup (with optional logging)
#

# 1) Locate this script’s directory so logs always end up alongside it
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGDIR="$SCRIPT_DIR/logs"
mkdir -p "$LOGDIR"

# 2) Defaults: only write a log on failure unless --log is passed
FORCE_LOG=0
LOGFILE=""

#--- Load secrets ---
# 1) Locate this script’s directory
SCRIPT_DIR="$(cd "$(dirname -- "$0")" && pwd)"

# 2) Compute project root (one level up from this script)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 3) Source the loader from the config folder by absolute path
. "$PROJECT_ROOT/config/load_secrets.sh"

# 3) Usage helper
usage() {
  cat <<EOF
Usage: $(basename "$0") [--log[=FILE]] [-h]

  --log[=FILE]   Always write full output to FILE.
                 If you omit '=FILE', defaults to:
                   $LOGDIR/$(basename "$0" .sh)-YYYYMMDD_HHMMSS.log

  -h, --help     Show this help and exit.
EOF
  exit 1
}

# 4) Parse command‑line flags
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

# 5) If logging was requested but no filename given, build a timestamped default
if [ "$FORCE_LOG" -eq 1 ] && [ -z "$LOGFILE" ]; then
  LOGFILE="$LOGDIR/$(basename "$0" .sh)-$(date +%Y%m%d_%H%M%S).log"
fi

# 6) Configuration defaults (can be overridden via env)
# INTERFACE=${INTERFACE:-em0}
# GIT_SERVER=${GIT_SERVER:-192.0.2.10}
# NETMASK=${NETMASK:-255.255.255.0}
# GATEWAY=${GATEWAY:-192.0.2.1}
# DNS1=${DNS1:-1.1.1.1}
# DNS2=${DNS2:-9.9.9.9}

#–––– Run all tests in a function so we can capture their output ––––
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

  #––– Begin Test Plan –––
  echo "1..12"

  # 1–3: Network interface & config file
  run_test "[ -f /etc/hostname.${INTERFACE} ]"                                                 "interface config file exists"
  run_test "grep -q \"^inet ${GIT_SERVER} ${NETMASK}\$\" /etc/hostname.${INTERFACE}"           "hostname.${INTERFACE} has correct 'inet IP MASK' line"
  run_test "grep -q \"^!route add default ${GATEWAY}\$\" /etc/hostname.${INTERFACE}"           "hostname.${INTERFACE} has correct default route"
  

  # 4–7: DNS & resolv.conf
  run_test "[ -f /etc/resolv.conf ]"                                                         "resolv.conf exists"
  run_test "grep -q \"nameserver ${DNS1}\" /etc/resolv.conf"                                 "resolv.conf contains DNS1"
  run_test "grep -q \"nameserver ${DNS2}\" /etc/resolv.conf"                                 "resolv.conf contains DNS2"
  assert_file_perm "/etc/resolv.conf" "644"                                                  "resolv.conf mode is 644"
  
  # 8-9: Default route in kernel
  run_test "ifconfig ${INTERFACE} | grep -q \"inet ${GIT_SERVER}\""                            "interface ${INTERFACE} is up with IP ${GIT_SERVER}"
  run_test "netstat -rn | grep -q '^default[[:space:]]*${GATEWAY}'"                            "default route via ${GATEWAY} present"

  # 10–12: SSH daemon & config
  run_test "grep -q \"^PermitRootLogin no\" /etc/ssh/sshd_config"                             "sshd_config disallows root login"
  run_test "grep -q \"^PasswordAuthentication no\" /etc/ssh/sshd_config"                      "sshd_config disallows password authentication"
  run_test "rcctl check sshd"                                                                 "sshd service is running"

  # 13-15: ROOT HISTFILE & HISTORY‐LENGTH
  run_test "grep -q '^export HISTFILE=/root/\.ksh_history' /root/.profile" \
           "root .profile sets HISTFILE to /root/.ksh_history"
  run_test "grep -q '^export HISTSIZE=5000' /root/.profile" \
           "root .profile sets HISTSIZE to 5000"
  run_test "grep -q '^export HISTCONTROL=ignoredups' /root/.profile" \
           "root .profile sets HISTCONTROL to ignoredups"

  #––– Summary –––
  echo ""
  if [ "$fails" -eq 0 ]; then
    echo "✅ All $tests tests passed."
  else
    echo "❌ $fails of $tests tests failed."
  fi

  return $fails
}

#–––– Wrapper to capture output and optionally log –––
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

#––– Execute –––
run_and_maybe_log

