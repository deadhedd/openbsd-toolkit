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

# -----------------------------------------------------------------------------
# Idempotency helpers (commented out until dry-run/rollback is implemented)
# -----------------------------------------------------------------------------
# DRY_RUN="false"
# ROLLBACK_CMDS=""
# run_cmd() {
#   _cmd="$1"
#   _rollback="$2"
#   if [ "$DRY_RUN" = "true" ]; then
#     printf '[DRY RUN] %s\n' "$_cmd"
#   else
#     eval "$_cmd"
#     ROLLBACK_CMDS="$_rollback\n$ROLLBACK_CMDS"
#   fi
# }
# safe_append_line() {
#   _file="$1"
#   _line="$2"
#   grep -Fqx "$_line" "$_file" 2>/dev/null && return 0
#   _tmp="$(mktemp)"
#   [ -f "$_file" ] && cp "$_file" "$_tmp"
#   printf '%s\n' "$_line" >> "$_tmp"
#   mv "$_tmp" "$_file"
# }
# safe_replace_line() {
#   _file="$1"
#   _pattern="$2"
#   _replacement="$3"
#   _tmp="$(mktemp)"
#   sed "s|$_pattern|$_replacement|" "$_file" > "$_tmp"
#   cmp -s "$_tmp" "$_file" || mv "$_tmp" "$_file"
#   rm -f "$_tmp"
# }
# safe_write() {
#   _file="$1"
#   _tmp="$(mktemp)"
#   cat > "$_tmp"
#   if ! cmp -s "$_tmp" "$_file" 2>/dev/null; then
#     mv "$_tmp" "$_file"
#   else
#     rm -f "$_tmp"
#   fi
# }
# rollback() {
#   printf '%s' "$ROLLBACK_CMDS" | while IFS= read -r _rb; do
#     [ -n "$_rb" ] && eval "$_rb"
#   done
# }
# trap rollback EXIT

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

# TODO: Idempotency: state detection

# Idempotency: rollback handling and dry-run mode example
# run_cmd "cat > /etc/hostname.${INTERFACE}" "rm -f /etc/hostname.${INTERFACE}"

# Idempotency: safe editing example
# safe_write "/etc/hostname.${INTERFACE}" <<EOF
# inet ${GIT_SERVER} ${NETMASK}
# !route add default ${GATEWAY}
# EOF

# Idempotency: replace+template with checksum example
# tmpl="$(mktemp)"
# cat > "$tmpl" <<EOF
# inet ${GIT_SERVER} ${NETMASK}
# !route add default ${GATEWAY}
# EOF
# old_sum="$(sha256 -q /etc/hostname.${INTERFACE} 2>/dev/null || true)"
# new_sum="$(sha256 -q "$tmpl")"
# [ "$old_sum" = "$new_sum" ] || cp "$tmpl" "/etc/hostname.${INTERFACE}"
# rm -f "$tmpl"
cat > "/etc/hostname.${INTERFACE}" <<EOF
inet ${GIT_SERVER} ${NETMASK}
!route add default ${GATEWAY}
EOF

# TODO: Idempotency: state detection

# Idempotency: rollback handling and dry-run mode example
# run_cmd "cat > /etc/resolv.conf" "rm -f /etc/resolv.conf"

# Idempotency: safe editing example
# safe_write /etc/resolv.conf <<EOF
# nameserver ${DNS1}
# nameserver ${DNS2}
# EOF

# Idempotency: replace+template with checksum example
# tmpl="$(mktemp)"
# cat > "$tmpl" <<EOF
# nameserver ${DNS1}
# nameserver ${DNS2}
# EOF
# old_sum="$(sha256 -q /etc/resolv.conf 2>/dev/null || true)"
# new_sum="$(sha256 -q "$tmpl")"
# [ "$old_sum" = "$new_sum" ] || cp "$tmpl" /etc/resolv.conf
# rm -f "$tmpl"
cat > /etc/resolv.conf <<EOF
nameserver ${DNS1}
nameserver ${DNS2}
EOF
# Idempotency: rollback handling and dry-run mode example
# run_cmd "chmod 644 /etc/resolv.conf" "chmod 000 /etc/resolv.conf"
chmod 644 /etc/resolv.conf

##############################################################################
# 5) Apply networking
##############################################################################

# Idempotency: rollback handling and dry-run mode example
# run_cmd "ifconfig ${INTERFACE} inet ${GIT_SERVER} netmask ${NETMASK} up" "ifconfig ${INTERFACE} inet delete"
ifconfig "${INTERFACE}" inet "${GIT_SERVER}" netmask "${NETMASK}" up
# Idempotency: rollback handling and dry-run mode example
# run_cmd "route add default ${GATEWAY}" "route delete default ${GATEWAY}"
route add default "${GATEWAY}"

##############################################################################
# 6) SSH hardening
##############################################################################

# Idempotency: rollback handling and dry-run mode example
# run_cmd "cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak && sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config" "mv /etc/ssh/sshd_config.bak /etc/ssh/sshd_config"

# Idempotency: safe editing example
# safe_replace_line /etc/ssh/sshd_config '^#*PermitRootLogin .*' 'PermitRootLogin no'

# Idempotency: replace+template with checksum example
# tmp_cfg="$(mktemp)"
# cp /etc/ssh/sshd_config "$tmp_cfg"
# sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' "$tmp_cfg"
# sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' "$tmp_cfg"
# old_sum="$(sha256 -q /etc/ssh/sshd_config 2>/dev/null || true)"
# new_sum="$(sha256 -q "$tmp_cfg")"
# [ "$old_sum" = "$new_sum" ] || cp "$tmp_cfg" /etc/ssh/sshd_config
# rm -f "$tmp_cfg"
sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
# TODO: Idempotency: replace+template with checksum

# Idempotency: rollback handling and dry-run mode example
# run_cmd "cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak && sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config" "mv /etc/ssh/sshd_config.bak /etc/ssh/sshd_config"

# Idempotency: safe editing example
# safe_replace_line /etc/ssh/sshd_config '^#*PasswordAuthentication .*' 'PasswordAuthentication no'
sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
# Idempotency: rollback handling and dry-run mode example
# run_cmd "rcctl restart sshd" "rcctl restart sshd"
rcctl restart sshd

##############################################################################
# 7) Root SSH authorized keys
##############################################################################

# TODO: Idempotency: state detection

ROOT_KEYS="${ROOT_SSH_PUBLIC_KEY_FILES:-$ROOT_SSH_PUBLIC_KEY_FILE}"
if [ -n "$ROOT_KEYS" ]; then
  SRC_DIR="$PROJECT_ROOT/config"
  SSH_DIR="/root/.ssh"
  # Idempotency: rollback handling and dry-run mode example
  # run_cmd "mkdir -p $SSH_DIR" "rmdir $SSH_DIR"
  mkdir -p "$SSH_DIR"
  # Idempotency: rollback handling and dry-run mode example
  # run_cmd "chmod 700 $SSH_DIR" "chmod 755 $SSH_DIR"
  chmod 700 "$SSH_DIR"
  AUTH_FILE="$SSH_DIR/authorized_keys"
  : > "$AUTH_FILE"
  for key in $ROOT_KEYS; do
    if [ -f "$SRC_DIR/$key" ]; then
      cat "$SRC_DIR/$key" >> "$AUTH_FILE"
    else
      printf 'warning: root ssh key file "%s" not found in %s\n' "$key" "$SRC_DIR" >&2
    fi
  done
  # Idempotency: rollback handling and dry-run mode example
  # run_cmd "chmod 600 $AUTH_FILE" "chmod 644 $AUTH_FILE"
  chmod 600 "$AUTH_FILE"
fi

##############################################################################
# 8) Root history
##############################################################################

# TODO: Idempotency: use state detection

# Idempotency: rollback handling and dry-run mode example
# run_cmd "cat >> /root/.profile" "cp /root/.profile.bak /root/.profile"

# Idempotency: safe editing example
# safe_append_line /root/.profile 'export HISTFILE=/root/.ksh_history'
# safe_append_line /root/.profile 'export HISTSIZE=5000'
# safe_append_line /root/.profile 'export HISTCONTROL=ignoredups'

# Idempotency: replace+template with checksum example
# tmp_profile="$(mktemp)"
# cat /root/.profile > "$tmp_profile" 2>/dev/null || true
# cat >> "$tmp_profile" <<'EOF'
# export HISTFILE=/root/.ksh_history
# export HISTSIZE=5000
# export HISTCONTROL=ignoredups
# EOF
# old_sum="$(sha256 -q /root/.profile 2>/dev/null || true)"
# new_sum="$(sha256 -q "$tmp_profile")"
# [ "$old_sum" = "$new_sum" ] || mv "$tmp_profile" /root/.profile
# rm -f "$tmp_profile"
cat << 'EOF' >> /root/.profile
export HISTFILE=/root/.ksh_history
export HISTSIZE=5000
export HISTCONTROL=ignoredups
EOF
# Idempotency: rollback handling and dry-run mode example
# run_cmd ". /root/.profile" ":"
. /root/.profile # shellcheck will show an issue, but its expected and OK

echo "base-system: system configuration complete!"
