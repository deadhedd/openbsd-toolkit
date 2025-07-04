#!/bin/sh
#
# setup_github.sh - GitHub deploy key & repo Bootstrap
# Usage: ./setup_github.sh
set -e

#--- Load secrets ---
# 1) Locate this script’s directory
SCRIPT_DIR="$(cd "$(dirname -- "$0")" && pwd)"

# 2) Compute project root (one level up from this script)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 3) Source the loader from the config folder by absolute path
. "$PROJECT_ROOT/config/load-secrets.sh"

#––– Determine script dir for deploy_key –––
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DEPLOY_KEY="$SCRIPT_DIR/deploy_key"

#––– Config (override via env) –––
# LOCAL_DIR=${LOCAL_DIR:-/root/openbsd-server}
# GITHUB_REPO=${GITHUB_REPO:-git@github.com:deadhedd/openbsd-server.git}

# 1. Deploy key
if [ ! -f "$DEPLOY_KEY" ]; then
  echo "ERROR: deploy_key not found at $DEPLOY_KEY"; exit 1
fi
mkdir -p /root/.ssh                             # TESTED (#1)
cp "$DEPLOY_KEY"    /root/.ssh/id_ed25519       # TESTED (#2)
chmod 600          /root/.ssh/id_ed25519        # TESTED (#3)

# 2. known_hosts
ssh-keyscan github.com >> /root/.ssh/known_hosts  # TESTED (#4 AND 5)

# 3. Clone or update your server-repo
if [ ! -d "${LOCAL_DIR}/.git" ]; then
  git clone "${GITHUB_REPO}" "${LOCAL_DIR}"      # TESTED (#6)
else
  cd "${LOCAL_DIR}"
  git pull                                       # TESTED (#6)
fi

echo "✅ GitHub configuration complete."

