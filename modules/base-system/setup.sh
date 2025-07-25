#!/bin/sh
#
# setup.sh — General system configuration for OpenBSD Server (base‑system module)
# Usage: ./setup.sh [--debug[=FILE]] [-h]

# 1) Locate project root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export PROJECT_ROOT

# 2) Load logging system and parse --debug
# shellcheck source=../../logs/logging.sh
. "$PROJECT_ROOT/logs/logging.sh"
parse_logging_flags "$@"
set -- $REMAINING_ARGS

module_name="$(basename "$SCRIPT_DIR")"
if [ "$DEBUG_MODE" -eq 1 ]; then
  set -vx  # enable xtrace
  init_logging "setup-$module_name"
fi

# 3) Load secrets (INTERFACE, GIT_SERVER, NETMASK, GATEWAY, DNS1, DNS2)
. "$PROJECT_ROOT/config/load_secrets.sh"

# 4) Write interface config
cat > "/etc/hostname.${INTERFACE}" <<-EOF
inet ${GIT_SERVER} ${NETMASK}
!route add default ${GATEWAY}
EOF

# 5) Write resolv.conf
cat > /etc/resolv.conf <<-EOF
nameserver ${DNS1}
nameserver ${DNS2}
EOF
chmod 644 /etc/resolv.conf

# 6) Bring up interface & default route
ifconfig "${INTERFACE}" inet "${GIT_SERVER}" netmask "${NETMASK}" up
route add default "${GATEWAY}"

# 7) SSH hardening
sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
rcctl restart sshd

# 8) Root history settings
cat << 'EOF' >> /root/.profile
export HISTFILE=/root/.ksh_history
export HISTSIZE=5000
export HISTCONTROL=ignoredups
EOF
. /root/.profile

echo "✅ base‑system: system configuration complete."
