#!/bin/sh
#
# setup_github_config.sh - GitHub deploy key & repo Bootstrap
# Usage: ./setup_github_config.sh
set -e

#––– Determine script dir for deploy_key –––
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)       # (not tested)
DEPLOY_KEY="$SCRIPT_DIR/deploy_key"             # (not tested)

#––– Config (override via env) –––
SETUP_DIR=${SETUP_DIR:-/root/openbsd-server}    # (not tested)
GITHUB_REPO=${GITHUB_REPO:-git@github.com:deadhedd/openbsd-server.git}  # (not tested)

# 1. Deploy key
if [ ! -f "$DEPLOY_KEY" ]; then
  echo "ERROR: deploy_key not found at $DEPLOY_KEY"; exit 1  # UNTESTED error path
fi
mkdir -p /root/.ssh                             # PARTIALLY TESTED (implied by id_ed25519 test)
cp "$DEPLOY_KEY"    /root/.ssh/id_ed25519       # TESTED (deploy key present)
chmod 600          /root/.ssh/id_ed25519        # TESTED (deploy key mode is 600)

# 2. known_hosts
ssh-keyscan github.com >> /root/.ssh/known_hosts  # TESTED (known_hosts exists & contains github.com)

# 3. Clone or update your server-repo
if [ ! -d "${SETUP_DIR}/.git" ]; then
  git clone "${GITHUB_REPO}" "${SETUP_DIR}"      # UNTESTED
else
  cd "${SETUP_DIR}"
  git pull                                       # UNTESTED
fi

echo "✅ GitHub configuration complete."

