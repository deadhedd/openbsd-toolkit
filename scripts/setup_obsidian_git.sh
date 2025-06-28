#!/bin/sh
#
# setup_obsidian_sync.sh - Git-backed Obsidian vault setup
# Usage: ./setup_obsidian_sync.sh
set -e

#––– Config (override via env) –––
REG_USER=${REG_USER:-obsidian}           # TESTED
GIT_USER=${GIT_USER:-git}                # TESTED
VAULT=${VAULT:-vault}                    # TESTED

# 1. Install required packages
pkg_add -v git                           # TESTED

# 2. Create users with correct shells
# Function to remove password for a user on OpenBSD
remove_password() {
  user="$1"
  echo "Removing password for user '$user' (empty password field)"
  # Safely rewrite master.passwd without using sed -i
  tmpfile=$(mktemp)                      # UNTESTED
  $ESC sed -E "s/^${user}:[^:]*:/${user}::/" /etc/master.passwd > "$tmpfile"  # UNTESTED
  $ESC mv "$tmpfile" /etc/master.passwd  # UNTESTED
  # Rebuild password database
  $ESC pwd_mkdb -p /etc/master.passwd    # UNTESTED
}

# --- Obsidian user creation ---
if ! id "$REG_USER" >/dev/null 2>&1; then
  echo "Creating system user '$REG_USER'"
  # TODO: Pull OBS_PASS from a secrets file instead of a default blank password
  $ESC useradd -m -s /bin/ksh "$REG_USER"        # TESTED
  if [ -n "${OBS_PASS}" ]; then
    echo "Setting provided OBS_PASS for '$REG_USER'"
    printf '%s\n' "$OBS_PASS" | $ESC passwd "$REG_USER"  # UNTESTED
  else
    # Remove password so no prompt on login
    remove_password "$REG_USER"                  # UNTESTED
  fi
else
  echo "User '$REG_USER' already exists; skipping creation"
fi

# --- Git user creation ---
if ! id "$GIT_USER" >/dev/null 2>&1; then
  echo "Creating system user '$GIT_USER'"
  # TODO: Pull GIT_PASS from a secrets file if shell access is ever required
  $ESC useradd -m -s /usr/local/bin/git-shell "$GIT_USER"  # TESTED
  if [ -n "${GIT_PASS}" ]; then
    echo "Setting provided GIT_PASS for '$GIT_USER'"
    printf '%s\n' "$GIT_PASS" | $ESC passwd "$GIT_USER"    # UNTESTED
  else
    # Remove password so no prompt on git-shell
    remove_password "$GIT_USER"                  # UNTESTED
  fi
else
  echo "User '$GIT_USER' already exists; skipping creation"
fi

# 3. Configure doas
cat > /etc/doas.conf <<-EOF              # TESTED
permit persist ${REG_USER} as root       # TESTED
permit nopass ${GIT_USER} as root cmd git*  # TESTED
EOF
chown root:wheel /etc/doas.conf          # TESTED
chmod 0440       /etc/doas.conf          # TESTED

# 4. Configure SSH for users
if grep -q '^AllowUsers' /etc/ssh/sshd_config; then
  sed -i "/^AllowUsers /c\\AllowUsers ${REG_USER} ${GIT_USER}" /etc/ssh/sshd_config  # TESTED
else
  echo "AllowUsers ${REG_USER} ${GIT_USER}" >> /etc/ssh/sshd_config  # TESTED
fi
rcctl restart sshd                       # UNTESTED

mkdir -p /home/${GIT_USER}/.ssh          # UNTESTED
chmod 700 /home/${GIT_USER}/.ssh         # UNTESTED
chown ${GIT_USER}:${GIT_USER} /home/${GIT_USER}/.ssh  # UNTESTED
echo "Now copy your public key into /home/${GIT_USER}/.ssh/authorized_keys"

# 5. Bare repo for vault
mkdir -p /home/${GIT_USER}/vaults        # TESTED
chown -R ${GIT_USER}:${GIT_USER} /home/${GIT_USER}/vaults  # TESTED
su -s /bin/sh - ${GIT_USER} -c "git init --bare /home/${GIT_USER}/vaults/${VAULT}.git"  # TESTED

# 6. Safe.directory for vault
su -s /bin/sh - ${REG_USER} -c "git config --global --add safe.directory /home/${GIT_USER}/vaults/${VAULT}.git"  # UNTESTED

# 7. Post-receive hook
HOOK=/home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive
cat > "$HOOK" << 'EOF'                   # TESTED
#!/bin/sh
# no-op post-receive hook
exit 0
EOF
chown ${GIT_USER}:${GIT_USER} "$HOOK"    # TESTED
chmod +x "$HOOK"                         # TESTED

# 8. Clone a working copy for obsidian user
mkdir -p /home/${REG_USER}/vaults        # TESTED
chown ${REG_USER}:${REG_USER} /home/${REG_USER}/vaults  # TESTED
su -s /bin/sh - ${REG_USER} -c "git clone /home/${GIT_USER}/vaults/${VAULT}.git /home/${REG_USER}/vaults/${VAULT}"  # TESTED

# 9. Safe.directory for working clone & initial commit
su -s /bin/sh - ${REG_USER} -c "git config --global --add safe.directory /home/${REG_USER}/vaults/${VAULT}"  # TESTED
su -s /bin/sh - ${REG_USER} -c "
  cd /home/${REG_USER}/vaults/${VAULT} &&
  git -c user.name='Obsidian User' \
      -c user.email='obsidian@example.com' \
      commit --allow-empty -m 'initial commit'
"                                        # UNTESTED

# 10. Configure HISTFILES
for u in "$REG_USER" "$GIT_USER"; do
  PROFILE="/home/${u}/.profile"
  echo 'export HISTFILE=$HOME/.histfile' >> "$PROFILE"   # TESTED
  echo 'touch $HISTFILE'             >> "$PROFILE"        # UNTESTED
done

echo "✅ Obsidian sync setup complete."

