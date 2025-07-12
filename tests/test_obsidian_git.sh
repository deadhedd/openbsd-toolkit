#!/bin/sh
#
# test_obsidian_git.sh – Verify git-backed Obsidian sync configuration (with optional logging)
# Usage: ./test_obsidian_git.sh [--log[=FILE]] [-h]
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
# 2) Logging defaults
#
FORCE_LOG=0
LOGFILE=""

#
# 3) Usage helper
#
usage() {
  cat <<EOF
Usage: $(basename "$0") [--log[=FILE]] [-h]

  --log, -l       Capture stdout, stderr & xtrace into:
                   \${PROJECT_ROOT}/logs/$(basename "$0" .sh)-TIMESTAMP.log
                 Or use --log=FILE to choose a custom path.

  -h, --help      Show this help and exit.
EOF
  exit 0
}

#
# 4) Parse flags
#
while [ $# -gt 0 ]; do
  case "$1" in
    -l|--log)        FORCE_LOG=1             ;;
    -l=*|--log=*)    FORCE_LOG=1; LOGFILE="${1#*=}" ;;
    -h|--help)       usage                   ;;
    *)               echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

#
# 5) Centralized logging init (handle tests/ or scripts/ subdir)
#
base="$(basename "$SCRIPT_DIR")"
if [ "$base" = "tests" ] || [ "$base" = "scripts" ]; then
  PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
else
  PROJECT_ROOT="$SCRIPT_DIR"
fi

LOG_HELPER="$PROJECT_ROOT/logs/logging.sh"
[ -f "$LOG_HELPER" ] || { echo "❌ logging.sh not found at $LOG_HELPER" >&2; exit 1; }
. "$LOG_HELPER"
init_logging "$0"

#
# 6) Load secrets
#
. "$PROJECT_ROOT/config/load_secrets.sh"

#
# 7) Prepare test parameters
#
: "${OBS_USER:?OBS_USER must be set in secrets}"
: "${GIT_USER:?GIT_USER must be set in secrets}"
: "${VAULT:?VAULT must be set in secrets}"
OBS_HOME="/home/${OBS_USER}"
BARE_REPO="/home/${GIT_USER}/vaults/${VAULT}.git"

#
# 8) Test definitions
#
run_test() {
  desc="$2"
  if eval "$1" >/dev/null 2>&1; then
    echo "ok - $desc"
  else
    echo "not ok - $desc"
    return 1
  fi
}

assert_file_perm() {
  path="$1"; want="$2"; desc="$3"
  run_test "stat -f '%Lp' \"$path\" | grep -q '^$want\$'" "$desc"
}

assert_git_safe() {
  repo="$1"; desc="$2"; user="${3:-$OBS_USER}"
  cfg="/home/$user/.gitconfig"
  run_test "grep -Eq '^[[:space:]]*safe\\.directory *= *$repo\$' \"$cfg\"" "$desc"
}

assert_user_shell() {
  user="$1"; shell="$2"; desc="$3"
  run_test "grep -q \"^$user:.*:$shell\$\" /etc/passwd" "$desc"
}

run_tests() {
  echo "1..49"

  run_test "command -v git" "git is installed"

  # Users & shells
  run_test "id $OBS_USER" "user '$OBS_USER' exists"
  assert_user_shell "$OBS_USER" "/bin/ksh" "shell for '$OBS_USER' is /bin/ksh"
  run_test "id $GIT_USER" "user '$GIT_USER' exists"
  assert_user_shell "$GIT_USER" "/usr/local/bin/git-shell" "shell for '$GIT_USER' is git-shell"

  # doas config
  run_test "[ -f /etc/doas.conf ]" "doas.conf exists"
  run_test "grep -q \"^permit persist $OBS_USER as root\$\" /etc/doas.conf" "doas.conf allows persist $OBS_USER"
  run_test "grep -q \"^permit nopass $GIT_USER as root cmd git\\*\" /etc/doas.conf" "doas.conf allows nopass $GIT_USER for git"
  run_test "stat -f '%Su:%Sg' /etc/doas.conf | grep -q '^root:wheel\$'" "doas.conf owned by root:wheel"
  assert_file_perm "/etc/doas.conf" "440" "/etc/doas.conf has mode 440"

  # SSH hardening
  run_test "grep -q \"^AllowUsers.*$OBS_USER.*$GIT_USER\" /etc/ssh/sshd_config" "sshd_config has AllowUsers"
  run_test "pgrep -x sshd >/dev/null" "sshd daemon running"

  # GIT_USER .ssh
  run_test "[ -d /home/$GIT_USER/.ssh ]" "ssh dir for $GIT_USER exists"
  assert_file_perm "/home/$GIT_USER/.ssh" "700" "ssh dir perms for $GIT_USER"
  run_test "stat -f '%Su:%Sg' /home/$GIT_USER/.ssh | grep -q '^$GIT_USER:$GIT_USER\$'" "ssh dir owner for $GIT_USER"

  # OBS_USER .ssh
  run_test "[ -d $OBS_HOME/.ssh ]" "ssh dir for $OBS_USER exists"
  assert_file_perm "$OBS_HOME/.ssh" "700" "ssh dir perms for $OBS_USER"
  run_test "stat -f '%Su:%Sg' $OBS_HOME/.ssh | grep -q '^$OBS_USER:$OBS_USER\$'" "ssh dir owner for $OBS_USER"

  # known_hosts for OBS_USER
  run_test "[ -f $OBS_HOME/.ssh/known_hosts ]" "known_hosts for $OBS_USER exists"
  run_test "grep -q '$SERVER' $OBS_HOME/.ssh/known_hosts" "known_hosts contains $SERVER"
  assert_file_perm "$OBS_HOME/.ssh/known_hosts" "644" "known_hosts perms for $OBS_USER"
  run_test "stat -f '%Su:%Sg' $OBS_HOME/.ssh/known_hosts | grep -q '^$OBS_USER:$OBS_USER\$'" "known_hosts owner correct"

  # safe.directory entries
  assert_git_safe "$BARE_REPO" "safe.directory for bare repo in $GIT_USER config" "$GIT_USER"
  assert_git_safe "/home/$OBS_USER/vaults/$VAULT" "safe.directory for work-tree in $GIT_USER config" "$GIT_USER"
  assert_git_safe "/home/$OBS_USER/vaults/$VAULT" "safe.directory for working clone in $OBS_USER config" "$OBS_USER"

  # post-receive hook
  run_test "[ -x $BARE_REPO/hooks/post-receive ]" "post-receive hook executable"
  run_test "grep -q '^#!/bin/sh' $BARE_REPO/hooks/post-receive" "hook shebang correct"

  # working clone
  run_test "[ -d $OBS_HOME/vaults/$VAULT/.git ]" "working clone exists"
  run_test "su - $OBS_USER -c \"git -C $OBS_HOME/vaults/$VAULT remote get-url origin | grep -q '$BARE_REPO'\"" "working clone origin correct"
  run_test "su - $OBS_USER -c \"git -C $OBS_HOME/vaults/$VAULT log -1 --pretty=%B | grep -q 'initial commit'\"" "initial commit present"

  echo ""
}

#
# 9) Wrapper to capture output and optionally log
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
# 10) Execute
#
run_and_maybe_log

