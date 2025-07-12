#!/bin/sh
#
# test_github.sh – Verify GitHub SSH key & repo bootstrap (with optional logging)
# Usage: ./test_github.sh [--log[=FILE]] [-h]
#

set -X

# 1) Locate this script’s directory so we can source logging.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 2) Logging defaults
FORCE_LOG=0
LOGFILE=""

# 3) Usage helper
usage() {
  cat <<EOF
Usage: $(basename "$0") [--log[=FILE]] [-h]

  --log, -l         Capture stdout, stderr and xtrace into:
                      ${SCRIPT_DIR}/logs/$(basename "$0" .sh)-TIMESTAMP.log
                    Or use --log=FILE to pick a custom path.

  -h, --help        Show this help and exit.
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


# 6) Turn on xtrace if you want command tracing in logs
# set -x

#--- Load secrets ---
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$PROJECT_ROOT/config/load_secrets.sh"

#–––– Test Framework ––––
run_tests() {
  local_dir=${LOCAL_DIR:-/root/openbsd-server}
  github_repo=${GITHUB_REPO:-git@github.com:deadhedd/openbsd-server.git}

  tests=0; fails=0

  run_test() {
    tests=$((tests+1))
    desc="$2"
    if eval "$1" >/dev/null 2>&1; then
      echo "ok $tests - $desc"
    else
      echo "not ok $tests - $desc"
      fails=$((fails+1))
    fi
  }

  assert_file_perm() {
    path=$1; want=$2; desc=$3
    run_test "stat -f '%Lp' $path | grep -q '^$want\$'" "$desc"
  }

  echo "1..7"
  run_test "[ -d /root/.ssh ]"                                                "root .ssh directory exists"
  run_test "[ -f /root/.ssh/id_ed25519 ]"                                      "deploy key present"
  assert_file_perm "/root/.ssh/id_ed25519" "600"                               "deploy key mode is 600"

  run_test "[ -f /root/.ssh/known_hosts ]"                                      "root known_hosts exists"
  run_test "grep -q '^github\\.com ' /root/.ssh/known_hosts"                   "known_hosts contains github.com"

  run_test "[ -d \$local_dir/.git ]"                                            "repository cloned into \$local_dir"
  run_test "grep -q \"url = \$github_repo\" \$local_dir/.git/config"            "remote origin set to GITHUB_REPO"

  echo ""
  if [ "$fails" -eq 0 ]; then
    echo "✅ All $tests tests passed."
  else
    echo "❌ $fails of $tests tests failed."
  fi

  return $fails
}

#–––– Wrapper to capture output and optionally log ––––
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

#––– Execute ––––
run_and_maybe_log

