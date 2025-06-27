#!/bin/sh
#
# setup_github_config.sh - GitHub deploy key & repo Bootstrap
# Usage: ./setup_github_config.sh
set -e

#––– Determine script dir for deploy_key –––
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DEPLOY_KEY="$SCRIPT_DIR/deploy_key"

#––– Config (override via env) –––
SETUP_DIR=${SETUP_DIR:-/root/openbsd-server}
GITHUB_REPO=${GITHUB_REPO:-git@github.com:deadhedd/openbsd-server.git}

# 1. Deploy key
if [ ! -f "$DEPLOY_KEY" ]; then
  echo "ERROR: deploy_key not found at $DEPLOY_KEY"; exit 1
fi
mkdir -p /root/.ssh
cp "$DEPLOY_KEY"    /root/.ssh/id_ed25519
chmod 600          /root/.ssh/id_ed25519

# 2. known_hosts
ssh-keyscan github.com >> /root/.ssh/known_hosts

# 3. Clone or update your server-repo
if [ ! -d "${SETUP_DIR}/.git" ]; then
  git clone "${GITHUB_REPO}" "${SETUP_DIR}"
else
  cd "${SETUP_DIR}"
  git pull
fi

echo "✅ GitHub configuration complete."
