#!/bin/sh
#
# setup_obsidian_sync.sh - Git-backed Obsidian vault setup
# Usage: ./setup_obsidian_sync.sh
set -e

#––– Config (override via env) –––
REG_USER=${REG_USER:-obsidian}
GIT_USER=${GIT_USER:-git}
VAULT=${VAULT:-vault}

# 1. Prepare git user’s SSH dir
mkdir -p /home/${GIT_USER}/.ssh
chmod 700 /home/${GIT_USER}/.ssh
chown ${GIT_USER}:${GIT_USER} /home/${GIT_USER}/.ssh
echo "Now copy your public key into /home/${GIT_USER}/.ssh/authorized_keys"

# 2. Bare repo for vault
mkdir -p /home/${GIT_USER}/vaults
chown -R ${GIT_USER}:${GIT_USER} /home/${GIT_USER}/vaults
su -s /bin/sh - ${GIT_USER} -c "git init --bare /home/${GIT_USER}/vaults/${VAULT}.git"

# 3. Safe.directory for vault
su -s /bin/sh - ${REG_USER} -c "git config --global --add safe.directory /home/${GIT_USER}/vaults/${VAULT}.git"

# 4. Post-receive hook
HOOK=/home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive
cat > "$HOOK" << 'EOF'
#!/bin/sh
# no-op post-receive hook
exit 0
EOF
chown ${GIT_USER}:${GIT_USER} "$HOOK"
chmod +x "$HOOK"

# 5. Clone a working copy for obsidian user
mkdir -p /home/${REG_USER}/vaults
chown ${REG_USER}:${REG_USER} /home/${REG_USER}/vaults
su -s /bin/sh - ${REG_USER} -c "git clone /home/${GIT_USER}/vaults/${VAULT}.git /home/${REG_USER}/vaults/${VAULT}"

# 6. Safe.directory for working clone & initial commit
su -s /bin/sh - ${REG_USER} -c "git config --global --add safe.directory /home/${REG_USER}/vaults/${VAULT}"
su -s /bin/sh - ${REG_USER} -c "cd /home/${REG_USER}/vaults/${VAULT} && git commit --allow-empty -m 'initial commit'"

echo "✅ Obsidian sync setup complete."
