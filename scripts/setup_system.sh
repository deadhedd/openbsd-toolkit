#!/bin/sh
#
# setup_system.sh - General system configuration for OpenBSD Server
# Usage: ./setup_system.sh [--log[=FILE]] [-h]
#

set -X

# 1) Locate this script’s directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 2) Logging defaults
FORCE_LOG=0
LOGFILE=""

# 3) Help text
usage() {
  cat <<EOF
Usage: $0 [--log[=FILE]] [-h]

  --log, -l           Capture stdout, stderr, and xtrace to a log file in:
                        ${SCRIPT_DIR}/logs/
                      Use --log=FILE to specify a custom path.

  -h, --help          Show this help and exit.
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
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

# 5) Centralized logging init
. "$SCRIPT_DIR/logs/logging.sh"
init_logging "$0"

# 6) Turn on xtrace for full visibility in logs
set -x

#--- Load secrets ---
# 7) Compute project root (one level up from this script)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 8) Source the loader from the config folder
. "$PROJECT_ROOT/config/load_secrets.sh"

#––– Config (override via env) –––
# INTERFACE=${INTERFACE:-em0}
# GIT_SERVER=${GIT_SERVER:-192.0.2.10}
# NETMASK=${NETMASK:-255.255.255.0}
# GATEWAY=${GATEWAY:-192.0.2.1}
# DNS1=${DNS1:-1.1.1.1}
# DNS2=${DNS2:-9.9.9.9}

# 1. Static network
cat > "/etc/hostname.${INTERFACE}" <<-EOF    # TESTED (#1)
inet ${GIT_SERVER} ${NETMASK}
!route add default ${GATEWAY}
EOF

cat > /etc/resolv.conf <<-EOF                # TESTED (#4)
nameserver ${DNS1}                           # TESTED (#5)
nameserver ${DNS2}                           # TESTED (#6)
EOF
chmod 644 /etc/resolv.conf                   # TESTED (#7)

ifconfig "${INTERFACE}" inet "${GIT_SERVER}" netmask "${NETMASK}" up  # TESTED (#8)
route add default "${GATEWAY}"                                       # TESTED (#9)

# 2. SSH hardening
sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config                 # TESTED (#10)
sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config   # TESTED (#11)
rcctl restart sshd                                                                        # TESTED (#12)

# 3. Root history settings
cat << 'EOF' >> /root/.profile
export HISTFILE=/root/.ksh_history      # TESTED (#13)
export HISTSIZE=5000                    # TESTED (#15)
export HISTCONTROL=ignoredups           # TESTED (#16)
EOF
. /root/.profile

echo "✅ System configuration complete."

