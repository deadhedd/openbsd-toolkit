#!/bin/sh
#
# modules/base-system/setup.sh — General system configuration for OpenBSD server
# Author: deadhedd
# Version: 1.0.0
# Updated: 2025-08-02
#
# Usage: sh setup.sh [--debug[=FILE]] [-h]
#
# Description:
#   Sets hostname, networking (ifconfig/route), /etc/resolv.conf, hardens SSH,
#   and configures root shell history. Assumes secrets/env vars are loaded.
#
# Deployment considerations:
#   Requires INTERFACE, GIT_SERVER, NETMASK, GATEWAY, DNS1, DNS2 from
#   config/load-secrets.sh. Fails early if those aren’t defined.
#
# Security note:
#   Enabling the --debug flag will log all executed commands *and their expanded
#   values* (via `set -vx`), including any exported secrets or credentials.
#   Use caution when sharing or retaining debug logs.
#
# See also:
#   - modules/base-system/test.sh
#   - logs/logging.sh
#   - config/load-secrets.sh


##############################################################################
# 0) Resolve paths
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export PROJECT_ROOT

##############################################################################
# 1) Help / banned flags prescan
##############################################################################

show_help() {
  cat <<EOF
  Usage: sh $(basename "$0") [options]

  Description:
    Set up system hostname, networking, and base packages

  Options:
    -h, --help        Show this help message and exit
    -d, --debug       Enable debug/xtrace and write a log file
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      show_help
      exit 0
      ;;
    -l|--log|-l=*|--log=*)
      printf '%s\n' "This script no longer supports --log. Did you mean --debug?" >&2
      exit 2
      ;;
  esac
done

##############################################################################
# 2) Parse flags and initialize logging
##############################################################################

# shellcheck source=logs/logging.sh
. "$PROJECT_ROOT/logs/logging.sh"
module_name="$(basename "$SCRIPT_DIR")"
start_logging_if_debug "setup-$module_name" "$@"

##############################################################################
# 3) Load secrets
##############################################################################

. "$PROJECT_ROOT/config/load-secrets.sh"

##############################################################################
# 4) Networking config files
##############################################################################

# TODO: Idempotency: state detection; safe editing or replace+template with checksum; rollback handling and dry-run mode
cat > "/etc/hostname.${INTERFACE}" <<EOF
inet ${GIT_SERVER} ${NETMASK}
!route add default ${GATEWAY}
EOF

# TODO: Idempotency: state detection; safe editing or replace+template with checksum; rollback handling and dry-run mode
cat > /etc/resolv.conf <<EOF
nameserver ${DNS1}
nameserver ${DNS2}
EOF
# TODO: Idempotency: Rollback handling and dry-run mode
chmod 644 /etc/resolv.conf

##############################################################################
# 5) Apply networking
##############################################################################

# TODO: Idempotency: Rollback handling and dry-run mode
ifconfig "${INTERFACE}" inet "${GIT_SERVER}" netmask "${NETMASK}" up
# TODO: Idempotency: Rollback handling and dry-run mode
route add default "${GATEWAY}"

##############################################################################
# 6) SSH hardening
##############################################################################

# TODO: Idempotency: Safe editing or replace+template with checksum; rollback handling and dry-run mode
sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
# TODO: Idempotency: Safe editing or replace+template with checksum; rollback handling and dry-run mode
sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
# TODO: Idempotency: Rollback handling and dry-run mode
rcctl restart sshd

##############################################################################
# 7) Root history
##############################################################################

# TODO: Idempotency: Use state detection; safe editing or replace+template with checksum; rollback handling and dry-run mode
cat << 'EOF' >> /root/.profile
export HISTFILE=/root/.ksh_history
export HISTSIZE=5000
export HISTCONTROL=ignoredups
EOF
. /root/.profile # shellcheck will show an issue, but its expected and OK

echo "base-system: system configuration complete!"
