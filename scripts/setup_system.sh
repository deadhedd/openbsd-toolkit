#!/bin/sh
#
# setup_system.sh - General system configuration for OpenBSD Server
# Usage: ./setup_system.sh
set -e

#––– Config (override via env) –––
INTERFACE=${INTERFACE:-em0}
STATIC_IP=${STATIC_IP:-192.0.2.10}
NETMASK=${NETMASK:-255.255.255.0}
GATEWAY=${GATEWAY:-192.0.2.1}
DNS1=${DNS1:-1.1.1.1}
DNS2=${DNS2:-9.9.9.9}

# 1. Static network
cat > "/etc/hostname.${INTERFACE}" <<-EOF
inet ${STATIC_IP} ${NETMASK}
!route add default ${GATEWAY}
EOF
cat > /etc/resolv.conf <<-EOF
nameserver ${DNS1}
nameserver ${DNS2}
EOF
ifconfig "${INTERFACE}" inet "${STATIC_IP}" netmask "${NETMASK}" up
route add default "${GATEWAY}"

# 2. SSH hardening
sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
rcctl restart sshd

# 3. Configure HISTFILE
# TODO (root)

echo "✅ System configuration complete."
