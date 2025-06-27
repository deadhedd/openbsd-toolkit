#!/bin/sh
#
# setup_system.sh - General system configuration for Obsidian-Git-Host
# Usage: ./setup_system.sh
set -e

#––– Config (override via env) –––
REG_USER=${REG_USER:-obsidian}
GIT_USER=${GIT_USER:-git}
INTERFACE=${INTERFACE:-em0}
STATIC_IP=${STATIC_IP:-192.0.2.10}
NETMASK=${NETMASK:-255.255.255.0}
GATEWAY=${GATEWAY:-192.0.2.1}
DNS1=${DNS1:-1.1.1.1}
DNS2=${DNS2:-9.9.9.9}

# 1. Install required packages
pkg_add -v git doas

# 2. Create users with correct shells
# Function to remove password for a user on OpenBSD
remove_password() {
  user="$1"
  echo "Removing password for user '$user' (empty password field)"
  # Safely rewrite master.passwd without using sed -i
  tmpfile=$(mktemp)
  $ESC sed -E "s/^${user}:[^:]*:/${user}::/" /etc/master.passwd > "$tmpfile"
  $ESC mv "$tmpfile" /etc/master.passwd
  # Rebuild password database
  $ESC pwd_mkdb -p /etc/master.passwd
}

# --- Obsidian user creation ---
if ! id "$REG_USER" >/dev/null 2>&1; then
  echo "Creating system user '$REG_USER'"
  # TODO: Pull OBS_PASS from a secrets file instead of a default blank password
  $ESC useradd -m -s /bin/ksh "$REG_USER"
  if [ -n "${OBS_PASS}" ]; then
    echo "Setting provided OBS_PASS for '$REG_USER'"
    printf '%s\n' "$OBS_PASS" | $ESC passwd "$REG_USER"
  else
    # Remove password so no prompt on login
    remove_password "$REG_USER"
  fi
else
  echo "User '$REG_USER' already exists; skipping creation"
fi

# --- Git user creation ---
if ! id "$GIT_USER" >/dev/null 2>&1; then
  echo "Creating system user '$GIT_USER'"
  # TODO: Pull GIT_PASS from a secrets file if shell access is ever required
  $ESC useradd -m -s /usr/local/bin/git-shell "$GIT_USER"
  if [ -n "${GIT_PASS}" ]; then
    echo "Setting provided GIT_PASS for '$GIT_USER'"
    printf '%s\n' "$GIT_PASS" | $ESC passwd "$GIT_USER"
  else
    # Remove password so no prompt on git-shell
    remove_password "$GIT_USER"
  fi
else
  echo "User '$GIT_USER' already exists; skipping creation"
fi

# 3. Configure doas
cat > /etc/doas.conf <<-EOF
permit persist ${REG_USER} as root
permit nopass ${GIT_USER} as root cmd git*
EOF
chown root:wheel /etc/doas.conf
chmod 0440       /etc/doas.conf

# 4. Static network
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

# 5. SSH hardening
sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
if grep -q '^AllowUsers' /etc/ssh/sshd_config; then
  sed -i "/^AllowUsers /c\\AllowUsers ${REG_USER} ${GIT_USER}" /etc/ssh/sshd_config
else
  echo "AllowUsers ${REG_USER} ${GIT_USER}" >> /etc/ssh/sshd_config
fi
rcctl restart sshd

# 6. Configure HISTFILE in profiles
for u in "$REG_USER" "$GIT_USER"; do
  PROFILE="/home/${u}/.profile"
  echo 'export HISTFILE=$HOME/.histfile' >> "$PROFILE"
  echo 'touch $HISTFILE'             >> "$PROFILE"
done

echo "✅ System configuration complete."
