#!/bin/sh
#
# setup_github.sh - GitHub deploy key & repo bootstrap
# Usage: ./setup_github.sh [--log[=FILE]] [-h]
#

set -x  # -e: exit on error, -x: trace commands

# 1) Figure out where this script lives
case "$0" in
  */*) SCRIPT_PATH="$0" ;;
  *)   SCRIPT_PATH="$(command -v -- "$0" 2>/dev/null || printf "%s" "$0")" ;;
esac
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"

# 2) Logging defaults
FORCE_LOG=0
LOGFILE=""

# 3) Usage helper
usage() {
  cat <<EOF
Usage: $0 [--log[=FILE]] [-h]

  --log, -l       Always capture stdout, stderr & xtrace into:
                   ${SCRIPT_DIR%/scripts}/logs/$(basename "$0" .sh)-TIMESTAMP.log
                 Or use --log=FILE to pick a custom path.

  -h, --help      Show this help and exit.
EOF
  exit 0
}

# 4) Parse flags
while [ $# -gt 0 ]; do
  case "$1" in
    -l|--log)        FORCE_LOG=1             ;;
    -l=*|--log=*)    FORCE_LOG=1; LOGFILE="${1#*=}" ;;
    -h|--help)       usage                   ;;
    *)               echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# 5) Centralized logging init
PROJECT_ROOT="${SCRIPT_DIR%/scripts}"  # if SCRIPT_DIR ends in /scripts strip it
LOG_HELPER="$PROJECT_ROOT/logs/logging.sh"
if [ ! -f "$LOG_HELPER" ]; then
  echo "❌ logging.sh not found at $LOG_HELPER" >&2
  exit 1
fi
. "$LOG_HELPER"
init_logging "$0"

# 6) Load secrets
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$PROJECT_ROOT/config/load_secrets.sh"

# 7) Deploy-key path
DEPLOY_KEY="$SCRIPT_DIR/deploy_key"

# 8) Validate deploy key
if [ ! -f "$DEPLOY_KEY" ]; then
  echo "ERROR: deploy_key not found at $DEPLOY_KEY"
  exit 1
fi

# 9) Install key
mkdir -p /root/.ssh
cp "$DEPLOY_KEY" /root/.ssh/id_ed25519
chmod 600 /root/.ssh/id_ed25519

# 10) Add GitHub to known_hosts
ssh-keyscan github.com >> /root/.ssh/known_hosts

# 11) Clone or update repo
if [ -z "$LOCAL_DIR" ] || [ -z "$GITHUB_REPO" ]; then
  echo "ERROR: LOCAL_DIR or GITHUB_REPO not set in secrets" >&2
  exit 1
fi

if [ ! -d "${LOCAL_DIR}/.git" ]; then
  git clone "${GITHUB_REPO}" "${LOCAL_DIR}"
else
  git -C "${LOCAL_DIR}" pull
fi

echo "✅ GitHub configuration complete."

