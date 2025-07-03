#!/bin/sh
#
# test_github.sh – Verify GitHub SSH key & repo bootstrap (with optional logging)
#

#--- Load secrets ---
. "$(dirname "$0")/load-secrets.sh"

# 1) Locate this script’s directory so logs always end up alongside it
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGDIR="$SCRIPT_DIR/logs"
mkdir -p "$LOGDIR"

# 2) Defaults: only write a log on failure unless --log is passed
FORCE_LOG=0
LOGFILE=""

# 3) Usage helper
usage() {
  cat <<EOF
Usage: $(basename "$0") [--log[=FILE]] [-h]

  --log[=FILE]   Always write full output to FILE.
                 If you omit '=FILE', defaults to:
                   $LOGDIR/$(basename "$0" .sh)-YYYYMMDD_HHMMSS.log

  -h, --help     Show this help and exit.
EOF
  exit 1
}

# 4) Parse command‑line flags
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

# 5) If logging was requested but no filename given, build a timestamped default
if [ "$FORCE_LOG" -eq 1 ] && [ -z "$LOGFILE" ]; then
  LOGFILE="$LOGDIR/$(basename "$0" .sh)-$(date +%Y%m%d_%H%M%S).log"
fi

#–––– Test Framework ––––
run_tests() {
  # optionally allow override, but default must match setup script
  setup_dir=${SETUP_DIR:-/root/openbsd-server}
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

  #––– Begin Test Plan –––
  echo "1..7"


  run_test "[ -d /root/.ssh ]"                                                "root .ssh directory exists"
  run_test "[ -f /root/.ssh/id_ed25519 ]"                                    "deploy key present"
  assert_file_perm "/root/.ssh/id_ed25519" "600"                              "deploy key mode is 600"

  run_test "[ -f /root/.ssh/known_hosts ]"                                    "root known_hosts exists"
  run_test "grep -q '^github\\.com ' /root/.ssh/known_hosts"                 "known_hosts contains github.com"

  run_test "[ -d \$setup_dir/.git ]"                                          "repository cloned into \$setup_dir"

  run_test "grep -q \"url = \$github_repo\" \$setup_dir/.git/config"          "remote origin set to GITHUB_REPO"

  #––– Summary –––
  echo ""
  if [ "$fails" -eq 0 ]; then
    echo "✅ All $tests tests passed."
  else
    echo "❌ $fails of $tests tests failed."
  fi

  return $fails
}

#–––– Wrapper to capture output and optionally log –––
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

#––– Execute –––
run_and_maybe_log

