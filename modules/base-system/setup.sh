#!/bin/sh
#
# setup.sh — General system configuration for OpenBSD Server (base‑system module)

set -x  # -e: exit on any error; -x: trace commands

# 1) Locate project root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# 2) Load secrets (INTERFACE, GIT_SERVER, NETMASK, GATEWAY, DNS1, DNS2)
. "$PROJECT_ROOT/config/load_secrets.sh"

# 3) Write interface config
cat > "/etc/hostname.${INTERFACE}" <<-EOF
inet ${GIT_SERVER} ${NETMASK}
!route add default ${GATEWAY}
EOF

# 4) Write resolv.conf
cat > /etc/resolv.conf <<-EOF
nameserver ${DNS1}
nameserver ${DNS2}
EOF
chmod 644 /etc/resolv.conf

# 5) Bring up interface & default route
ifconfig "${INTERFACE}" inet "${GIT_SERVER}" netmask "${NETMASK}" up
route add default "${GATEWAY}"

# 6) SSH hardening
sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
rcctl restart sshd

# 7) Root history settings
cat << 'EOF' >> /root/.profile
export HISTFILE=/root/.ksh_history
export HISTSIZE=5000
export HISTCONTROL=ignoredups
EOF
. /root/.profile

echo "✅ base‑system: system configuration complete."

