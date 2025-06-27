#!/bin/sh
#
# test_obsidian_sync.sh – Verify git-backed Obsidian sync configuration (with optional logging)
#

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

  assert_git_safe() {
    repo=$1; desc=$2
    run_test "su - ${REG_USER:-obsidian} -c \"git config --global --get-all safe.directory | grep -q '^$repo\$'\"" "$desc"
  }

  assert_user_shell() {
    user=$1; shell=$2; desc=$3
    run_test "grep -q \"^$user:.*:$shell\$\" /etc/passwd" "$desc"
  }

  #––– Begin Test Plan –––
  echo "1..7"

  # configuration defaults
  REG_USER=${REG_USER:-obsidian}
  GIT_USER=${GIT_USER:-git}
  VAULT=${VAULT:-vault}

  run_test "id $REG_USER" "user '$REG_USER' exists"
  assert_user_shell "$REG_USER" "/bin/ksh"                  "shell for '$REG_USER' is /bin/ksh"
  run_test "id $GIT_USER" "user '$GIT_USER' exists"
  assert_user_shell "$GIT_USER" "/usr/local/bin/git-shell" "shell for '$GIT_USER' is git-shell"
  run_test "command -v git"  "git is installed"
  run_test "[ -d /home/${GIT_USER}/vaults/${VAULT}.git ]"                               "bare repo exists"
  run_test "stat -f '%Su' /home/${GIT_USER}/vaults/${VAULT}.git | grep -q '^${GIT_USER}\$'" "bare repo is owned by '${GIT_USER}'"
  run_test "[ -x /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive ]"               "post-receive hook is executable"
  run_test "stat -f '%Su:%Sg' /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive | grep -q '^${GIT_USER}:${GIT_USER}\$'" "post-receive hook owned by ${GIT_USER}"
  run_test "[ -f /home/${GIT_USER}/vaults/${VAULT}.git/HEAD ]"                              "bare repo HEAD exists"
  run_test "[ -d /home/${REG_USER}/vaults/${VAULT}/.git ]"                                  "working clone exists for '${REG_USER}'"
  assert_git_safe "/home/${REG_USER}/vaults/${VAULT}"                                      "safe.directory configured for working clone"
  run_test "grep -q '^export HISTFILE=\\\$HOME/.histfile' /home/${REG_USER}/.profile"    "${REG_USER} .profile sets HISTFILE"
  run_test "grep -q '^export HISTFILE=\\\$HOME/.histfile' /home/${GIT_USER}/.profile"    "${GIT_USER} .profile sets HISTFILE"
  run_test "[ -d /home/${REG_USER} ]"                              "home directory for ${REG_USER} exists"
  run_test "stat -f '%Su' /home/${REG_USER} | grep -q '^${REG_USER}\$'" "${REG_USER} owns their home"
  run_test "[ -d /home/${GIT_USER} ]"                              "home directory for ${GIT_USER} exists"
  run_test "stat -f '%Su' /home/${GIT_USER} | grep -q '^${GIT_USER}\$'"   "${GIT_USER} owns their home"
  run_test "grep -q \"^AllowUsers.*${REG_USER}.*${GIT_USER}\" /etc/ssh/sshd_config" "sshd_config has AllowUsers"

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
