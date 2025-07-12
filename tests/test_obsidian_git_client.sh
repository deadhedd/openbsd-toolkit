#!/bin/sh
#
# test_obsidian_git_client.sh – Verify client-side Obsidian Git sync (with optional logging)
# Usage: ./test_obsidian_git_client.sh [--log[=FILE]] [-h]
#

set -e

# 1) Locate this script’s directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 2) Logging defaults
FORCE_LOG=0
LOGFILE=""

# 3) Usage helper
usage() {
  cat <<EOF
Usage: $(basename "$0") [--log[=FILE]] [-h]

  --log, -l           Capture stdout, stderr, and xtrace to:
                        ${SCRIPT_DIR}/../logs/$(basename "$0" .sh)-TIMESTAMP.log
                      Or use --log=FILE to pick a custom path.

  -h, --help          Show this help and exit.
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
      usage
      ;;
  esac
  shift
done

# 5) Centralized logging init
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
#!/bin/sh
#
# setup_all.sh - Run all three setup scripts in sequence
# Usage: ./setup_all.sh [--log[=FILE]] [-h]
#

set -x

# 1) Where this script lives
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 2) Logging defaults
FORCE_LOG=0
LOGFILE=""

# 3) Help text
usage() {
  cat <<EOF
Usage: $0 [--log[=FILE]] [-h]

  --log, -l           Capture stdout, stderr, and xtrace to a log file in:
                        ${SCRIPT_DIR}/logs/
                      Use --log=FILE to specify a custom path.

  -h, --help          Show this help and exit.
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

# 5) Centralized logging init
if     [ -f "$SCRIPT_DIR/logs/logging.sh" ]; then
  LOG_HELPER="$SCRIPT_DIR/logs/logging.sh"
elif   [ -f "$SCRIPT_DIR/../logs/logging.sh" ]; then
  LOG_HELPER="$SCRIPT_DIR/../logs/logging.sh"
else
  echo "❌ logging.sh not found in logs/ or ../logs/" >&2
  exit 1
fi

. "$LOG_HELPER"
init_logging "$0"

# 6) Turn on xtrace so everything shows up in the log
set -x

# 7) Run the three setup scripts
echo "👉 Running system setup…"
sh "$SCRIPT_DIR/scripts/setup_system.sh"

echo "👉 Running Obsidian-git setup…"
sh "$SCRIPT_DIR/scripts/setup_obsidian_git.sh"

echo "👉 Running GitHub setup…"
sh "$SCRIPT_DIR/scripts/setup_github.sh"

echo ""
echo "✅ All setup scripts completed successfully."

# 6) (Optional) enable xtrace for detailed logs
# set -x

# 7) Load config from secrets.env
SECRETS="$PROJECT_ROOT/config/secrets.env"
if [ ! -f "$SECRETS" ]; then
  echo "❌ secrets.env not found at $SECRETS"
  exit 1
fi
set -a; . "$SECRETS"; set +a

# 8) Derived paths
BARE_REPO="/home/${GIT_USER}/vaults/${VAULT}.git"
WORK_TREE="/home/${OBS_USER}/vaults/${VAULT}"
LOCAL_VAULT="$HOME/${VAULT}"

# 9) Test helper
run_test() {
  if eval "$1"; then
    echo "ok - $2"
  else
    echo "not ok - $2"
  fi
}

# 10) Run tests
run_tests() {
  run_test "ssh-add -l | grep -q id_ed25519"                             "ssh-agent running and id_ed25519 loaded"
  run_test "grep -q \"$SERVER\" ~/.ssh/known_hosts"                       "known_hosts contains $SERVER"
  run_test "[ -d \"$LOCAL_VAULT/.git\" ]"                                 "local vault is a Git repo"
  run_test "ssh ${GIT_USER}@${SERVER} [ -d \"$BARE_REPO\" ]"              "remote bare repo exists"
  run_test "ssh ${GIT_USER}@${SERVER} [ -x \"$BARE_REPO/hooks/post-receive\" ]" \
           "post-receive hook is present and executable"
  run_test "git -C \"$LOCAL_VAULT\" pull origin"                         "git pull succeeds over SSH"
  cd "$LOCAL_VAULT" || exit 1
  echo "# test $(date +%s)" >> test-sync.md
  git add test-sync.md
  git commit -m "TDD sync test"
  run_test "git push origin HEAD"                                        "git push succeeds over SSH"
}

# 11) Wrapper to capture output and optionally log
run_and_maybe_log() {
  TMP="$(mktemp)" || exit 1
  if ! run_tests >"$TMP" 2>&1; then
    echo "🛑 $(basename "$0") FAILED — dumping full log to $LOGFILE"
    cat "$TMP" | tee "$LOGFILE"
    rm -f "$TMP"
    exit 1
  else
    if [ "$FORCE_LOG" -eq 1 ]; then
      echo "✅ $(basename "$0") passed — writing full log to $LOGFILE"
      cat "$TMP" >>"$LOGFILE"
    else
      cat "$TMP"
    fi
    rm -f "$TMP"
  fi
}

# 12) Execute
run_and_maybe_log

