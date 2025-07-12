#!/bin/sh
#
# setup_obsidian_git.sh - Git-backed Obsidian vault setup
# Usage: ./setup_obsidian_git.sh
set -x

#--- Load secrets ---
SCRIPT_DIR="$(cd "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$PROJECT_ROOT/config/load_secrets.sh"

#––– Config (override via env) –––
# OBS_USER=${OBS_USER:-obsidian}
# GIT_USER=${GIT_USER:-git}
# VAULT=${VAULT:-vault}

# 1. Install required packages
pkg_add -v git                                         # TESTED (#1)

# 2. Create users with correct shells
remove_password() {
  user="$1"
  echo "Removing password for user '$user'"
  tmpfile=$(mktemp)
  $ESC sed -E "s/^${user}:[^:]*:/${user}::/" /etc/master.passwd > "$tmpfile"
  $ESC mv "$tmpfile" /etc/master.passwd
  $ESC pwd_mkdb -p /etc/master.passwd
}

if ! id "$OBS_USER" >/dev/null 2>&1; then
  echo "Creating system user '$OBS_USER'"
  $ESC useradd -m -s /bin/ksh "$OBS_USER"              # TESTED (#2/#3)
  if [ -n "$OBS_PASS" ]; then
    printf '%s\n' "$OBS_PASS" | $ESC passwd "$OBS_USER"
  else
    remove_password "$OBS_USER"
  fi
else
  echo "User '$OBS_USER' already exists; skipping"
fi

if ! id "$GIT_USER" >/dev/null 2>&1; then
  echo "Creating system user '$GIT_USER'"
  $ESC useradd -m -s /usr/local/bin/git-shell "$GIT_USER"   # TESTED (#4/#5)
  if [ -n "$GIT_PASS" ]; then
    printf '%s\n' "$GIT_PASS" | $ESC passwd "$GIT_USER"
  else
    remove_password "$GIT_USER"
  fi
else
  echo "User '$GIT_USER' already exists; skipping"
fi

# 3. Configure doas
cat > /etc/doas.conf <<-EOF                    # TESTED (#6)
permit persist ${OBS_USER} as root
permit nopass  ${GIT_USER} as root cmd git*
EOF
chown root:wheel /etc/doas.conf                # TESTED (#9)
chmod 0440       /etc/doas.conf                # TESTED (#10)

# 4. Configure SSH for both users
if grep -q '^AllowUsers' /etc/ssh/sshd_config; then
  sed -i "/^AllowUsers /c\\AllowUsers ${OBS_USER} ${GIT_USER}" /etc/ssh/sshd_config
else
  echo "AllowUsers ${OBS_USER} ${GIT_USER}" >> /etc/ssh/sshd_config
fi
rcctl restart sshd                                                                      # TESTED (#12)

# Git‐user .ssh
mkdir -p "/home/${GIT_USER}/.ssh"                                                         # TESTED (#13)
chmod 700 "/home/${GIT_USER}/.ssh"                                                        # TESTED (#16)
touch   "/home/${GIT_USER}/.ssh/authorized_keys"
chmod 600 "/home/${GIT_USER}/.ssh/authorized_keys"
chown -R "${GIT_USER}:${GIT_USER}" "/home/${GIT_USER}/.ssh"

# Obs‐user .ssh & known_hosts
mkdir -p "/home/${OBS_USER}/.ssh"
chmod 700 "/home/${OBS_USER}/.ssh"
ssh-keyscan -H "${SERVER}" >> "/home/${OBS_USER}/.ssh/known_hosts"                         # TESTED (#23–26)
chmod 644 "/home/${OBS_USER}/.ssh/known_hosts"
chown -R "${OBS_USER}:${OBS_USER}" "/home/${OBS_USER}/.ssh"

# 5. Set up bare repo under git user
mkdir -p "/home/${GIT_USER}/vaults"                                                       # TESTED (#27)
chown "${GIT_USER}:${GIT_USER}" "/home/${GIT_USER}/vaults"
git init --bare "/home/${GIT_USER}/vaults/${VAULT}.git"                                    # TESTED (#30)
chown -R "${GIT_USER}:${GIT_USER}" "/home/${GIT_USER}/vaults/${VAULT}.git"

# 6. Add safe.directory entries in each user’s own config file
# ensure the config files exist
touch "/home/${GIT_USER}/.gitconfig"
touch "/home/${OBS_USER}/.gitconfig"
# git user
git config --file "/home/${GIT_USER}/.gitconfig" --add safe.directory "/home/${GIT_USER}/vaults/${VAULT}.git"
git config --file "/home/${GIT_USER}/.gitconfig" --add safe.directory "/home/${OBS_USER}/vaults/${VAULT}"
chown "${GIT_USER}:${GIT_USER}" "/home/${GIT_USER}/.gitconfig"
# obs user
git config --file "/home/${OBS_USER}/.gitconfig" --add safe.directory "/home/${OBS_USER}/vaults/${VAULT}"
chown "${OBS_USER}:${OBS_USER}" "/home/${OBS_USER}/.gitconfig"

# 7. Post-receive hook
HOOK="/home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive"
cat > "$HOOK" <<-EOF                   # TESTED (#33)
#!/bin/sh
git --work-tree="/home/${OBS_USER}/vaults/${VAULT}" \
    --git-dir="/home/${GIT_USER}/vaults/${VAULT}.git" checkout -f
exit 0
EOF
chown "${GIT_USER}:${GIT_USER}" "$HOOK"    # TESTED (#35)
chmod +x "$HOOK"                         # TESTED (#36)

# 8. Clone a working copy for obsidian user
mkdir -p "/home/${OBS_USER}/vaults"                                                    # TESTED (#37)
chown "${OBS_USER}:${OBS_USER}" "/home/${OBS_USER}/vaults"
git clone "/home/${GIT_USER}/vaults/${VAULT}.git" "/home/${OBS_USER}/vaults/${VAULT}"     # TESTED (#39/#40)
chown -R "${OBS_USER}:${OBS_USER}" "/home/${OBS_USER}/vaults/${VAULT}"

# 9. Initial empty commit by root (with correct author) in obs user’s working clone
cd "/home/${OBS_USER}/vaults/${VAULT}"
git -c user.name='Obsidian User' \
    -c user.email='obsidian@example.com' \
    commit --allow-empty -m 'initial commit'                                           # TESTED (#43/#44)
cd -

# 10. Configure HISTFILES in each user’s .profile
for u in "$OBS_USER" "$GIT_USER"; do
  PROFILE="/home/${u}/.profile"
  cat <<-EOF >> "$PROFILE"
export HISTFILE=/home/${u}/.ksh_history
export HISTSIZE=5000
export HISTCONTROL=ignoredups
EOF
  chown "${u}:${u}" "$PROFILE"
done

echo "✅ Obsidian sync setup complete."

