#!/bin/sh
#
# setup_github.sh - GitHub deploy key & repo bootstrap
# Usage: ./setup_github.sh [--log[=FILE]] [-h]
#

set -x

# 1) Locate this script’s directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 2) Logging defaults
FORCE_LOG=0
LOGFILE=""

# 3) Usage helper
usage() {
  cat <<EOF
Usage: $0 [--log[=FILE]] [-h]

  --log, -l           Capture stdout, stderr and xtrace to a log in:
                        ${SCRIPT_DIR}/logs/
                      Use --log=FILE to pick a different path.

  -h, --help          Show this message and exit.
EOF
  exit 0
}

# 4) Parse flags
while [ $# -gt 0 ]; do
  case "$1" in
    -l|--log)
      FORCE_LOG=1
      ;;
    -l=*|--log=*)
      FORCE_LOG=1
      LOGFILE="${1#*=}"
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

# 5) If logging, set up FIFO+tee
if [ "$FORCE_LOG" -eq 1 ]; then
  LOGDIR="${SCRIPT_DIR}/logs"
  mkdir -p "$LOGDIR"

  [ -z "$LOGFILE" ] && \
    LOGFILE="$LOGDIR/setup_github-$(date '+%Y%m%d_%H%M%S').log"

  echo "ℹ️  Logging to $LOGFILE"

  FIFO="$LOGDIR/setup_github-$$.fifo"
  mkfifo "$FIFO"
  tee -a "$LOGFILE" <"$FIFO" &
  TEE_PID=$!
  exec >"$FIFO" 2>&1
  rm -f "$FIFO"
fi

# 6) Turn on xtrace for full visibility
set -x

#--- Load secrets ---
# 7) Compute project root (one level up)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$PROJECT_ROOT/config/load_secrets.sh"

#––– Determine deploy key path –––
DEPLOY_KEY="$SCRIPT_DIR/deploy_key"

#––– Config (override via env) –––
# LOCAL_DIR=${LOCAL_DIR:-/root/openbsd-server}
# GITHUB_REPO=${GITHUB_REPO:-git@github.com:deadhedd/openbsd-server.git}

# 1. Deploy key
if [ ! -f "$DEPLOY_KEY" ]; then
  echo "ERROR: deploy_key not found at $DEPLOY_KEY"
  exit 1
fi
mkdir -p /root/.ssh                              # TESTED (#1)
cp "$DEPLOY_KEY" /root/.ssh/id_ed25519            # TESTED (#2)
chmod 600 /root/.ssh/id_ed25519                   # TESTED (#3)

# 2. known_hosts
ssh-keyscan github.com >> /root/.ssh/known_hosts   # TESTED (#4 AND 5)

# 3. Clone or update your server-repo
if [ ! -d "${LOCAL_DIR}/.git" ]; then
  git clone "${GITHUB_REPO}" "${LOCAL_DIR}"       # TESTED (#6)
else
  cd "${LOCAL_DIR}"
  git pull                                        # TESTED (#6)
fi

echo "✅ GitHub configuration complete."

