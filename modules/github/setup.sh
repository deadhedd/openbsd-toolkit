#!/bin/sh
#
# setup.sh — GitHub deploy key & repo bootstrap (github module)
# Usage: ./setup.sh [--debug[=FILE]] [-h]

# 1) Determine script & project paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export PROJECT_ROOT

# 2) Load logging system and parse --debug
# shellcheck source=../../logs/logging.sh
. "$PROJECT_ROOT/logs/logging.sh"
parse_logging_flags "$@"
set -- $REMAINING_ARGS

module_name="$(basename "$SCRIPT_DIR")"
if [ "$DEBUG_MODE" -eq 1 ]; then
  set -vx  # enable xtrace
  init_logging "setup-$module_name"
fi

# 3) Load secrets (LOCAL_DIR, GITHUB_REPO)
. "$PROJECT_ROOT/config/load_secrets.sh"

# 4) Deploy-key path
DEPLOY_KEY="$PROJECT_ROOT/config/deploy_key"

# 5) Validate deploy key exists
[ -f "$DEPLOY_KEY" ] || { echo "ERROR: deploy_key not found at $DEPLOY_KEY" >&2; exit 1; }

# 6) Install key into root's SSH
mkdir -p /root/.ssh
cp "$DEPLOY_KEY" /root/.ssh/id_ed25519
chmod 600 /root/.ssh/id_ed25519

# 7) Add GitHub to known_hosts
ssh-keyscan github.com >> /root/.ssh/known_hosts

# 8) Validate secrets for cloning
: "LOCAL_DIR=$LOCAL_DIR"       # ensure variable is set
: "GITHUB_REPO=$GITHUB_REPO"   # ensure variable is set

[ -n "$LOCAL_DIR" ]   || { echo "ERROR: LOCAL_DIR not set" >&2; exit 1; }
[ -n "$GITHUB_REPO" ] || { echo "ERROR: GITHUB_REPO not set" >&2; exit 1; }

# 9) Clone or update the repo
if [ ! -d "${LOCAL_DIR}/.git" ]; then
  git clone "$GITHUB_REPO" "$LOCAL_DIR"
else
  git -C "$LOCAL_DIR" pull
fi

echo "✅ github: GitHub configuration complete."
