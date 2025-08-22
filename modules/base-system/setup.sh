#!/bin/sh
#
# modules/base-system/setup.sh — General system configuration for OpenBSD server
# Author: deadhedd
# Version: 1.0.2
# Updated: 2025-08-22
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

# Merge unique tokens in a directive line without clobbering existing values.
safe_replace_line() {
  _file="$1"
  _directive="$2"
  shift 2
  _values="$*"
  if [ -f "$_file" ] && grep -q "^${_directive} " "$_file"; then
    _existing="$(grep "^${_directive} " "$_file" | head -n1 | cut -d' ' -f2-)"
    _combined="$(printf '%s\n%s\n' "$_existing" "$_values" | tr ' ' '\n' | sort -u | tr '\n' ' ')"
    _combined="$(printf '%s' "$_combined" | sed 's/[[:space:]]*$//')"
    sed -i "/^${_directive} /c\\${_directive} ${_combined}" "$_file"
  else
    echo "${_directive} ${_values}" >> "$_file"
  fi
}

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

. "$PROJECT_ROOT/config/load-secrets.sh" "Base System"

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

##############################################################################
# 7) Admin user & SSH access
##############################################################################

[ -n "$ADMIN_USER" ] || { echo "ERROR: ADMIN_USER not set" >&2; exit 1; }

# Create admin user if missing
if ! id "$ADMIN_USER" >/dev/null 2>&1; then
  # Idempotency: rollback handling and dry-run mode example
  # run_cmd "useradd -m -G wheel -s /bin/ksh $ADMIN_USER" "userdel $ADMIN_USER"
  useradd -m -G wheel -s /bin/ksh "$ADMIN_USER"
fi

# Set admin password if provided; otherwise lock the account
if [ -n "$ADMIN_PASSWORD" ]; then
  pw_hash="$(encrypt -b "$ADMIN_PASSWORD")"
  # Idempotency: rollback handling and dry-run mode example
  # run_cmd "usermod -p '$pw_hash' $ADMIN_USER" "passwd -u $ADMIN_USER"
  usermod -p "$pw_hash" "$ADMIN_USER"
else
  # Idempotency: rollback handling and dry-run mode example
  # run_cmd "usermod -p '*' $ADMIN_USER" "passwd -u $ADMIN_USER"
  usermod -p '*' "$ADMIN_USER"
fi

CONFIG_DIR="$PROJECT_ROOT/config"
SSH_KEY_VARS=$(env | awk -F= '/_SSH_PUBLIC_KEY_FILE=/{print $1}')
[ -n "$SSH_KEY_VARS" ] || { echo "ERROR: no *_SSH_PUBLIC_KEY_FILE variables set" >&2; exit 1; }

ADMIN_HOME="/home/$ADMIN_USER"
SSH_DIR="$ADMIN_HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
: > "$AUTH_KEYS"
for var in $SSH_KEY_VARS; do
  key_file=$(eval echo "\$$var")
  key_path="$CONFIG_DIR/$key_file"
  if [ -f "$key_path" ]; then
    cat "$key_path" >> "$AUTH_KEYS"
  else
    echo "WARNING: missing SSH public key file $key_path" >&2
  fi
done
safe_replace_line /etc/ssh/sshd_config "AllowUsers" "${ADMIN_USER}"
chmod 600 "$AUTH_KEYS"
chown -R "$ADMIN_USER:$ADMIN_USER" "$SSH_DIR"
rcctl restart sshd

##############################################################################
# 8) Doas configuration
##############################################################################

DOAS_CONF="/etc/doas.conf"
# TODO: Idempotency: implement checks to avoid duplicate entries
echo "permit nopass ${ADMIN_USER} as root" >> "$DOAS_CONF"
chown root:wheel "$DOAS_CONF"
chmod 440 "$DOAS_CONF"

##############################################################################
# 9) Root history
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

#
##############################################################################
# 10) Admin history
##############################################################################

cat << EOF >> "$ADMIN_HOME/.profile"
export HISTFILE=$ADMIN_HOME/.ksh_history
export HISTSIZE=5000
export HISTCONTROL=ignoredups
EOF
chown "$ADMIN_USER:$ADMIN_USER" "$ADMIN_HOME/.profile"
chmod 644 "$ADMIN_HOME/.profile"

echo "base-system: system configuration complete!"
