#!/bin/sh
#
# test_obsidian_git_client.sh – Verify client-side Obsidian Git sync (with optional logging)
# Usage: ./test_obsidian_git_client.sh [--log[=FILE]] [-h]
#

set -ex  # -e: exit on error; -x: trace commands

#
# 1) Locate this script’s real path
#
case "$0" in
  */*) SCRIPT_PATH="$0" ;;
  *)   SCRIPT_PATH="$(command -v -- "$0" 2>/dev/null || printf "%s" "$0")" ;;
esac
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"

#
# 2) Determine project root (strip off /tests if present)
#
base="$(basename "$SCRIPT_DIR")"
if [ "$base" = "tests" ] || [ "$base" = "scripts" ]; then
  PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
else
  PROJECT_ROOT="$SCRIPT_DIR"
fi

#
# 3) Logging defaults
#
FORCE_LOG=0
LOGFILE=""

#
# 4) Usage helper
#
usage() {
  cat <<EOF
Usage: $(basename "$0") [--log[=FILE]] [-h]

  --log, -l       Capture stdout, stderr & xtrace into:
                   ${PROJECT_ROOT}/logs/$(basename "$0" .sh)-TIMESTAMP.log
                 Or use --log=FILE to choose a custom path.

  -h, --help      Show this help and exit.
EOF
  exit 0
}

#
# 5) Parse flags
#
while [ $# -gt 0 ]; do
  case "$1" in
    -l|--log)
      FORCE_LOG=1
      ;;
    -l=*|--log=*)
      FORCE_LOG=1; LOGFILE="${1#*=}"
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

#
# 6) Centralized logging init
#
LOG_HELPER="$PROJECT_ROOT/logs/logging.sh"
[ -f "$LOG_HELPER" ] || { echo "❌ logging.sh not found at $LOG_HELPER" >&2; exit 1; }
. "$LOG_HELPER"
init_logging "$0"

#
# 7) Load configuration
#
SECRETS="$PROJECT_ROOT/config/secrets.env"
[ -f "$SECRETS" ] || { echo "❌ secrets.env not found at $SECRETS" >&2; exit 1; }
set -a; . "$SECRETS"; set +a

#
# 8) Derived paths
#
BARE_REPO="/home/${GIT_USER}/vaults/${VAULT}.git"
WORK_TREE="/home/${OBS_USER}/vaults/${VAULT}"
LOCAL_VAULT="$HOME/${VAULT}"

#
# 9) Test helper
#
run_test() {
  if eval "$1" >/dev/null 2>&1; then
    echo "ok - $2"
  else
    echo "not ok - $2"
    return 1
  fi
}

#
# 10) Run tests
#
run_tests() {
  echo "1..7"
  run_test "ssh-add -l | grep -q id_ed25519"         "ssh-agent running and id_ed25519 loaded"
  run_test "grep -q \"$SERVER\" ~/.ssh/known_hosts"  "known_hosts contains $SERVER"
  run_test "[ -d \"$LOCAL_VAULT/.git\" ]"            "local vault is a Git repo"
  run_test "ssh ${GIT_USER}@${SERVER} [ -d \"$BARE_REPO\" ]" \
       "remote bare repo exists"
  run_test "ssh ${GIT_USER}@${SERVER} [ -x \"$BARE_REPO/hooks/post-receive\" ]" \
       "post-receive hook is present and executable"
  run_test "git -C \"$LOCAL_VAULT\" pull origin"     "git pull succeeds over SSH"
  cd "$LOCAL_VAULT"
  echo "# test $(date +%s)" >> test-sync.md
  git add test-sync.md
  git commit -m "TDD sync test"
  run_test "git push origin HEAD"                    "git push succeeds over SSH"
}

#
# 11) Wrapper to capture output and optionally log
#
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

#
# 12) Execute
#
run_and_maybe_log

