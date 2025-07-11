#!/bin/sh
#
# setup_system.sh - General system configuration for OpenBSD Server
# Usage: ./setup_system.sh
set -e

#--- Load secrets ---
# 1) Locate this script’s directory
SCRIPT_DIR="$(cd "$(dirname -- "$0")" && pwd)"

# 2) Compute project root (one level up from this script)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 3) Source the loader from the config folder by absolute path
. "$PROJECT_ROOT/config/load_secrets.sh"

#––– Config (override via env) –––
# INTERFACE=${INTERFACE:-em0}
# GIT_SERVER=${GIT_SERVER:-192.0.2.10}
# NETMASK=${NETMASK:-255.255.255.0}
# GATEWAY=${GATEWAY:-192.0.2.1}
# DNS1=${DNS1:-1.1.1.1}
# DNS2=${DNS2:-9.9.9.9}

# 1. Static network
# TESTED PERSISTENT IP (#2)
# TESTED DEFAULT ROUTE (#3)
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

# TESTED ROOT PROFILE SETS HISTFILE (#13)
# TESTED ROOT PROFILE SETS HISTSIZE (#15)
# TESTED ROOT PROFILE SETS HISTCONTROL (#16)
cat << 'EOF' >> /root/.profile
export HISTFILE=/root/.ksh_history
export HISTSIZE=5000
export HISTCONTROL=ignoredups
EOF
. /root/.profile

echo "✅ System configuration complete."

