#!/bin/sh
#
# setup_system.sh - General system configuration for OpenBSD Server
# Usage: ./setup_system.sh [--log[=FILE]] [-h]
#

set -ex  # -e: exit on any error, -x: trace all commands

#
# 1) Find where this script lives
#
case "$0" in
  */*) SCRIPT_PATH="$0" ;;
  *)   SCRIPT_PATH="$(command -v -- "$0" 2>/dev/null || printf "%s" "$0")" ;;
esac
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"

#
# 2) Logging defaults
#
FORCE_LOG=0
LOGFILE=""

#
# 3) Usage helper
#
usage() {
  cat <<EOF
Usage: $0 [--log[=FILE]] [-h]

  --log, -l       Capture stdout, stderr & xtrace into:
                   \${SCRIPT_DIR%/scripts}/logs/$(basename "$0" .sh)-TIMESTAMP.log
                 Or use --log=FILE to choose a custom path.

  -h, --help      Show this help and exit.
EOF
  exit 0
}

#
# 4) Parse flags
#
while [ $# -gt 0 ]; do
  case "$1" in
    -l|--log)        FORCE_LOG=1             ;;
    -l=*|--log=*)    FORCE_LOG=1; LOGFILE="${1#*=}" ;;
    -h|--help)       usage                   ;;
    *)               echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

#
# 5) Centralized logging init
#
PROJECT_ROOT="${SCRIPT_DIR%/scripts}"
LOG_HELPER="$PROJECT_ROOT/logs/logging.sh"
[ -f "$LOG_HELPER" ] || { echo "❌ logging.sh not found at $LOG_HELPER" >&2; exit 1; }
. "$LOG_HELPER"
init_logging "$0"

#
# 6) Load secrets
#
. "$PROJECT_ROOT/config/load_secrets.sh"

#
# 7) System configuration steps
#

# 1. Write interface config
cat > "/etc/hostname.${INTERFACE}" <<-EOF
inet ${GIT_SERVER} ${NETMASK}
!route add default ${GATEWAY}
EOF

# 2. Write resolv.conf
cat > /etc/resolv.conf <<-EOF
nameserver ${DNS1}
nameserver ${DNS2}
EOF
chmod 644 /etc/resolv.conf

# 3. Bring up interface and route
ifconfig "${INTERFACE}" inet "${GIT_SERVER}" netmask "${NETMASK}" up
route add default "${GATEWAY}"

# 4. SSH hardening
sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
rcctl restart sshd

# 5. Root history settings
cat << 'EOF' >> /root/.profile
export HISTFILE=/root/.ksh_history
export HISTSIZE=5000
export HISTCONTROL=ignoredups
EOF
. /root/.profile

echo "✅ System configuration complete."

