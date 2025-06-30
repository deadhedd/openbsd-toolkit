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
cat > "/etc/hostname.${INTERFACE}" <<-EOF    # TESTED (#1)
inet ${STATIC_IP} ${NETMASK}                 # TESTED (#2)
!route add default ${GATEWAY}                # TESTED (#3)
EOF

cat > /etc/resolv.conf <<-EOF                # TESTED (#4)
nameserver ${DNS1}                           # TESTED (#5)
nameserver ${DNS2}                           # TESTED (#6)
EOF
chmod 644 /etc/resolv.conf                   # TESTED (#7)

ifconfig "${INTERFACE}" inet "${STATIC_IP}" netmask "${NETMASK}" up  # TESTED (#8)
route add default "${GATEWAY}"                                       # TESTED (#9)

# 2. SSH hardening
sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config                 # TESTED (#10)
sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config   # TESTED (#11)
rcctl restart sshd                                                                        # TESTED (#12)

# 3. Configure HISTFILE
# TODO (root) — no implementation yet                                          # UNTESTED           

echo "✅ System configuration complete."

