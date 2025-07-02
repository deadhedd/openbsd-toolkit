#!/bin/sh
#
# setup_obsidian_git.sh - Git-backed Obsidian vault setup
# Usage: ./setup_obsidian_git.sh
set -e

#––– Config (override via env) –––
REG_USER=${REG_USER:-obsidian}
GIT_USER=${GIT_USER:-git}
VAULT=${VAULT:-vault}

# 1. Install required packages
pkg_add -v git                                         # TESTED (#1)

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
  $ESC useradd -m -s /bin/ksh "$REG_USER"                                      # TESTED (#2 AND 3)
  if [ -n "${OBS_PASS}" ]; then
    echo "Setting provided OBS_PASS for '$REG_USER'"
    printf '%s\n' "$OBS_PASS" | $ESC passwd "$REG_USER"                        # TESTED (#52)
  else
    # Remove password so no prompt on login
    remove_password "$REG_USER"                                                # TESTED (#52)
  fi
else
  echo "User '$REG_USER' already exists; skipping creation"
fi

# --- Git user creation ---
if ! id "$GIT_USER" >/dev/null 2>&1; then
  echo "Creating system user '$GIT_USER'"
  # TODO: Pull GIT_PASS from a secrets file if shell access is ever required
  $ESC useradd -m -s /usr/local/bin/git-shell "$GIT_USER"                      # TESTED (#4 AND 5)
  if [ -n "${GIT_PASS}" ]; then
    echo "Setting provided GIT_PASS for '$GIT_USER'"
    printf '%s\n' "$GIT_PASS" | $ESC passwd "$GIT_USER"                        # TESTED (#53)
  else
    # Remove password so no prompt on git-shell
    remove_password "$GIT_USER"                                                # TESTED (#53)
  fi
else
  echo "User '$GIT_USER' already exists; skipping creation"
fi

# 3. Configure doas
# TESTED REG_USER PERMIT PERSIST (#7)
# TESTED GIT_USER PERMIT NOPASS (#8)
cat > /etc/doas.conf <<-EOF                    # TESTED (#6)
permit persist ${REG_USER} as root
permit nopass ${GIT_USER} as root cmd git*
EOF
chown root:wheel /etc/doas.conf                # TESTED (#9)
chmod 0440       /etc/doas.conf                # TESTED (#10)

# 4. Configure SSH for users
if grep -q '^AllowUsers' /etc/ssh/sshd_config; then
  sed -i "/^AllowUsers /c\\AllowUsers ${REG_USER} ${GIT_USER}" /etc/ssh/sshd_config     # TESTED (#11)
else
  echo "AllowUsers ${REG_USER} ${GIT_USER}" >> /etc/ssh/sshd_config                     # TESTED (#11)
fi
rcctl restart sshd                                                                      # TESTED (#12)

mkdir -p /home/${GIT_USER}/.ssh                                                         # TESTED (#13)
chmod 700 /home/${GIT_USER}/.ssh                                                        # TESTED (#16)
chown ${GIT_USER}:${GIT_USER} /home/${GIT_USER}/.ssh                                    # TESTED (#14)
echo "Now copy your public key into /home/${GIT_USER}/.ssh/authorized_keys"

# 5. Bare repo for vault
mkdir -p /home/${GIT_USER}/vaults                                                       # TESTED (#27)
chown -R ${GIT_USER}:${GIT_USER} /home/${GIT_USER}/vaults                               # TESTED (#29)
su -s /bin/sh - ${GIT_USER} -c "git init --bare /home/${GIT_USER}/vaults/${VAULT}.git"  # TESTED (#30)

# 6. Safe.directory for vault
su -s /bin/sh - ${REG_USER} -c "git config --global --add safe.directory \
         /home/${GIT_USER}/vaults/${VAULT}.git"                                    # TESTED (#31)

# 7. Post-receive hook
HOOK=/home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive
cat > "$HOOK" << 'EOF'                   # TESTED (#33)
#!/bin/sh
# no-op post-receive hook
exit 0
EOF
                                         # TESTED (#34)
chown ${GIT_USER}:${GIT_USER} "$HOOK"    # TESTED (#35)
chmod +x "$HOOK"                         # TESTED (#36)

# 8. Clone a working copy for obsidian user
mkdir -p /home/${REG_USER}/vaults                                                    # TESTED (#37)
chown ${REG_USER}:${REG_USER} /home/${REG_USER}/vaults                               # TESTED (#38)
su -s /bin/sh - ${REG_USER} -c "git clone /home/${GIT_USER}/vaults/${VAULT}.git \
      /home/${REG_USER}/vaults/${VAULT}"                                             # TESTED (#39 AND 40)

# 9. Safe.directory for working clone & initial commit
su -s /bin/sh - ${REG_USER} -c "git config --global --add safe.directory \
      /home/${REG_USER}/vaults/${VAULT}"                                         # TESTED (#32)
su -s /bin/sh - ${REG_USER} -c "
  cd /home/${REG_USER}/vaults/${VAULT} &&
  git -c user.name='Obsidian User' \
      -c user.email='obsidian@example.com' \
      commit --allow-empty -m 'initial commit'
"                                                                                # TESTED (#43 AND 44)

# 10. Configure HISTFILES
for u in "$REG_USER" "$GIT_USER"; do
  PROFILE="/home/${u}/.profile"
  # TESTED ${u} PROFILE SETS HISTFILE (#46/#47)
  # TESTED ${u} PROFILE SETS HISTSIZE (#48/#49)
  # TESTED ${u} PROFILE SETS HISTCONTROL (#50/#51)
  cat <<EOF >> "$PROFILE"
export HISTFILE=/home/${u}/.ksh_history
export HISTSIZE=5000
export HISTCONTROL=ignoredups
EOF
done

echo "✅ Obsidian sync setup complete."

