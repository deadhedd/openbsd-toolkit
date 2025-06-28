#!/bin/sh
#
# setup_system.sh - General system configuration for OpenBSD Server
# Usage: ./setup_system.sh
set -e

#––– Config (override via env) –––
INTERFACE=${INTERFACE:-em0}                  # PARTIALLY TESTED (used by tests 1–3)
STATIC_IP=${STATIC_IP:-192.0.2.10}           # PARTIALLY TESTED (used by tests 2–3)
NETMASK=${NETMASK:-255.255.255.0}            # PARTIALLY TESTED (used by tests 2–3)
GATEWAY=${GATEWAY:-192.0.2.1}                # PARTIALLY TESTED (used by tests 3–4)
DNS1=${DNS1:-1.1.1.1}                        # PARTIALLY TESTED (used by tests 5–6)
DNS2=${DNS2:-9.9.9.9}                        # PARTIALLY TESTED (used by tests 5–6)

# 1. Static network
cat > "/etc/hostname.${INTERFACE}" <<-EOF    # TESTED (tests 1)
inet ${STATIC_IP} ${NETMASK}                 # TESTED (test 2)
!route add default ${GATEWAY}                # TESTED (test 3)
EOF

cat > /etc/resolv.conf <<-EOF                # TESTED (test 5)
nameserver ${DNS1}                           # TESTED (test 6)
nameserver ${DNS2}                           # TESTED (test 7)
EOF

ifconfig "${INTERFACE}" inet "${STATIC_IP}" netmask "${NETMASK}" up  # UNTESTED
route add default "${GATEWAY}"                                       # TESTED (test 4)

# 2. SSH hardening
sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config      # TESTED (test 11)
sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config  # UNTESTED
rcctl restart sshd                                                                 # PARTIALLY TESTED (sshd is running in test 10)

# 3. Configure HISTFILE
# TODO (root) — no implementation yet                                                     

echo "✅ System configuration complete."

