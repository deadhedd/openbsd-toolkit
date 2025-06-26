#!/bin/sh
#
# setup.sh - Configure OpenBSD server to pass test_openbsd_setup.sh
# Requires a GitHub deploy key file next to this script (deploy_key)
# Author: ChatGPT
# License: MIT or 0BSD

set -e

# Determine script directory (for deploy_key location)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DEPLOY_KEY="$SCRIPT_DIR/deploy_key"

# Configuration (override via env vars)
REG_USER=${REG_USER:-obsidian}
GIT_USER=${GIT_USER:-git}
VAULT=${VAULT:-vault}
INTERFACE=${INTERFACE:-em0}
STATIC_IP=${STATIC_IP:-192.0.2.10}
NETMASK=${NETMASK:-255.255.255.0}
GATEWAY=${GATEWAY:-192.0.2.1}
DNS1=${DNS1:-1.1.1.1}
DNS2=${DNS2:-9.9.9.9}
SETUP_DIR=${SETUP_DIR:-/root/openbsd-server}
GITHUB_REPO=${GITHUB_REPO:-git@github.com:deadhedd/openbsd-server.git}

# 1. Install required packages
pkg_add -v git doas

# 2. Create users with correct shells
if ! id "$REG_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/ksh "$REG_USER"
fi
if ! id "$GIT_USER" >/dev/null 2>&1; then
  useradd -m -s /usr/local/bin/git-shell "$GIT_USER"
fi

# 3. Configure doas for privilege escalation
cat > /etc/doas.conf <<-EOF
permit persist ${REG_USER} as root
permit nopass ${GIT_USER} as root cmd git*
EOF
# ensure correct ownership and permissions
chown root:wheel /etc/doas.conf
chmod 0440 /etc/doas.conf

# 4. Static network configuration
cat > "/etc/hostname.${INTERFACE}" <<-EOF
inet ${STATIC_IP} ${NETMASK}
!route add default ${GATEWAY}
EOF
cat > /etc/resolv.conf <<-EOF
nameserver ${DNS1}
nameserver ${DNS2}
EOF
# Activate interface and install default route immediately
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

# 6. Prepare for SSH key auth for vault user
mkdir -p /home/${GIT_USER}/.ssh
chmod 700 /home/${GIT_USER}/.ssh
chown ${GIT_USER}:${GIT_USER} /home/${GIT_USER}/.ssh
echo "Copy your ~/.ssh/id_rsa.pub into /home/${GIT_USER}/.ssh/authorized_keys now."

# 7. BARE REPO FOR VAULT
mkdir -p /home/${GIT_USER}/vaults
chown -R ${GIT_USER}:${GIT_USER} /home/${GIT_USER}/vaults
# Override git-shell to initialize
su -s /bin/sh - ${GIT_USER} -c "git init --bare /home/${GIT_USER}/vaults/${VAULT}.git"
# Mark bare repo safe for REG_USER
su -s /bin/sh - ${REG_USER} -c "git config --global --add safe.directory /home/${GIT_USER}/vaults/${VAULT}.git"
# Create a no-op post-receive hook and make it executable
HOOK=/home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive
cat > "$HOOK" << 'EOF'
#!/bin/sh
# no-op post-receive hook
exit 0
EOF
chown ${GIT_USER}:${GIT_USER} "$HOOK"
chmod +x "$HOOK"

# 8. CLONE A WORKING COPY
mkdir -p /home/${REG_USER}/vaults
chown ${REG_USER}:${REG_USER} /home/${REG_USER}/vaults
su -s /bin/sh - ${REG_USER} -c "git clone /home/${GIT_USER}/vaults/${VAULT}.git /home/${REG_USER}/vaults/${VAULT}"
# Mark working clone safe for tests
su -s /bin/sh - ${REG_USER} -c "git config --global --add safe.directory /home/${REG_USER}/vaults/${VAULT}"
# Create an initial empty commit so obsidian can push
su -s /bin/sh - ${REG_USER} -c "cd /home/${REG_USER}/vaults/${VAULT} && git commit --allow-empty -m 'initial commit'"


# 9. Deploy key for GitHub clone (from script directory)
if [ ! -f "$DEPLOY_KEY" ]; then
  echo "ERROR: Deploy key not found at $DEPLOY_KEY"
  echo "Place your private SSH key there (next to setup.sh) before running."
  exit 1
fi
mkdir -p /root/.ssh
cp "$DEPLOY_KEY" /root/.ssh/id_ed25519
chmod 600 /root/.ssh/id_ed25519
# Add GitHub to known_hosts to avoid prompt
ssh-keyscan github.com >> /root/.ssh/known_hosts

# 10. Clone/setup the script repo for future runs
if [ ! -d "${SETUP_DIR}/.git" ]; then
  git clone "${GITHUB_REPO}" "${SETUP_DIR}"
fi

# 11. Configure HISTFILE in user profiles
for u in "$REG_USER" "$GIT_USER"; do
  PROFILE="/home/${u}/.profile"
  echo 'export HISTFILE=$HOME/.histfile' >> "$PROFILE"
  echo 'touch $HISTFILE' >> "$PROFILE"
done

# End of setup
