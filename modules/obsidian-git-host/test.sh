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
# 5) Centralized logging init (handle tests/ or setup/ subdir)
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
: "\${OBS_USER:?OBS_USER must be set in secrets}"
: "\${GIT_USER:?GIT_USER must be set in secrets}"
: "\${VAULT:?VAULT must be set in secrets}"
OBS_HOME="/home/${OBS_USER}"
BARE_REPO="/home/${GIT_USER}/vaults/${VAULT}.git"
WORK_TREE="/home/${OBS_USER}/vaults/${VAULT}"

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
  run_test "stat -f '%Lp' \"$path\" | grep -q '^$want$'" "$desc"
}

assert_user_shell() {
  user="$1"; shell="$2"; desc="$3"
  run_test "grep -q \"^$user:.*:$shell$\" /etc/passwd" "$desc"
}

# ——— safe.directory helper ———
check_entry() {
  config_file="$1"
  dir="$2"
  user_label="$3"

  entries=$(git config --file "$config_file" --get-all safe.directory || true)
  printf '%s
' "$entries" |
    grep -Fx -- "$dir" >/dev/null || {
      echo "not ok - safe.directory for $user_label: $dir"
      return 1
    }
}

run_tests() {
  echo "1..49"

  run_test "command -v git" "git is installed"

  # Users & shells
  run_test "id $OBS_USER" "user '$OBS_USER' exists"
  assert_user_shell "$OBS_USER" "/bin/ksh" "shell for '$OBS_USER' is /bin/ksh"
  run_test "id $GIT_USER" "user '$GIT_USER' exists"
  assert_user_shell "$GIT_USER" "/usr/local/bin/git-shell" "shell for '$GIT_USER' is git-shell"
  
  # Group 'obsidian' exists
run_test "getent group vault" "group 'vault' exists"

# Both users are members of the 'obsidian' group
run_test "id -nG \$OBS_USER | grep -qw vault" "user '\$OBS_USER' is in group 'vault'"
run_test "id -nG \$GIT_USER | grep -qw vault" "user '\$GIT_USER' is in group 'vault'"

# Verify top‐level directory ownership
run_test "stat -f '%Su:%Sg' "$BARE_REPO" | grep -q '^git:vault$'" "ownership of '\$BARE_REPO' is 'git:vault'"

# Verify no files under the repo have wrong owner or group
run_test "! find \$BARE_REPO \\! -user git -group vault | grep -q ." "all files under '\$BARE_REPO' are owned by git:vault"

# All entries under the repo are group-readable
run_test "! find \$BARE_REPO \\! -perm -g=r | grep -q ." "all entries under '\$BARE_REPO' are group-readable"

# All entries under the repo are group-writable
run_test "! find \$BARE_REPO \\! -perm -g=w | grep -q ." "all entries under '\$BARE_REPO' are group-writable"

# All directories under the repo are group-executable
run_test "! find \$BARE_REPO -type d \\! -perm -g=x | grep -q ." "all directories under '\$BARE_REPO' are group-executable"

# Verify group setgid bit on all directories under the repo
run_test "! find \$BARE_REPO -type d \\! -perm -g+s | grep -q ." "all directories under '\$BARE_REPO' have the setgid bit set"


  # doas config
  run_test "[ -f /etc/doas.conf ]" "doas.conf exists"
  run_test "grep -q \"^permit persist $OBS_USER as root$\" /etc/doas.conf" "doas.conf allows persist $OBS_USER"
  run_test "grep -q \"^permit nopass $GIT_USER as root cmd git\\*\" /etc/doas.conf" "doas.conf allows nopass $GIT_USER for git"
  run_test "grep -q \"^permit nopass $GIT_USER as $OBS_USER cmd git\\*\" /etc/doas.conf" "doas.conf allows nopass $GIT_USER for working clone"
  run_test "stat -f '%Su:%Sg' /etc/doas.conf | grep -q '^root:wheel$'" "doas.conf owned by root:wheel"
  assert_file_perm "/etc/doas.conf" "440" "/etc/doas.conf has mode 440"

  # SSH hardening
  run_test "grep -q \"^AllowUsers.*$OBS_USER.*$GIT_USER\" /etc/ssh/sshd_config" "sshd_config has AllowUsers"
  run_test "pgrep -x sshd >/dev/null" "sshd daemon running"

  # GIT_USER .ssh
  run_test "[ -d /home/$GIT_USER/.ssh ]" "ssh dir for $GIT_USER exists"
  assert_file_perm "/home/$GIT_USER/.ssh" "700" "ssh dir perms for $GIT_USER"
  run_test "stat -f '%Su:%Sg' /home/$GIT_USER/.ssh | grep -q '^$GIT_USER:$GIT_USER$'" "ssh dir owner for $GIT_USER"

  # OBS_USER .ssh
  run_test "[ -d $OBS_HOME/.ssh ]" "ssh dir for $OBS_USER exists"
  assert_file_perm "$OBS_HOME/.ssh" "700" "ssh dir perms for $OBS_USER"
  run_test "stat -f '%Su:%Sg' $OBS_HOME/.ssh | grep -q '^$OBS_USER:$OBS_USER$'" "ssh dir owner for $OBS_USER"

  # known_hosts for OBS_USER
  run_test "[ -f $OBS_HOME/.ssh/known_hosts ]" "known_hosts for $OBS_USER exists"
  run_test "grep -q '$GIT_SERVER' $OBS_HOME/.ssh/known_hosts" "known_hosts contains $GIT_SERVER"
  assert_file_perm "$OBS_HOME/.ssh/known_hosts" "644" "known_hosts perms for $OBS_USER"
  run_test "stat -f '%Su:%Sg' $OBS_HOME/.ssh/known_hosts | grep -q '^$OBS_USER:$OBS_USER$'" "known_hosts owner correct"

  # safe.directory entries
  check_entry "/home/${GIT_USER}/.gitconfig" "$BARE_REPO" "${GIT_USER}"
  check_entry "/home/${GIT_USER}/.gitconfig" "$OBS_HOME/vaults/${VAULT}" "${GIT_USER}"
  check_entry "$OBS_HOME/.gitconfig" "$OBS_HOME/vaults/${VAULT}" "${OBS_USER}"

# post-receive hook
run_test "[ -x $BARE_REPO/hooks/post-receive ]" "post-receive hook executable"
run_test "grep -q '^#!/bin/sh' $BARE_REPO/hooks/post-receive" "hook shebang correct"

run_test "grep -q '^SHA=\\$(cat $BARE_REPO/refs/heads/master)$' $BARE_REPO/hooks/post-receive" \ # Possible issue with expansion, cat command may be getting run rather than checked for in the file
  "hook: SHA variable set correctly"

run_test "grep -q '^su - $OBS_USER -c \"/usr/local/bin/git --git-dir=$BARE_REPO --work-tree=$WORK_TREE checkout -f \$SHA\"$' $BARE_REPO/hooks/post-receive" \
  "hook: git checkout command correct"

run_test "grep -q '^exit 0$' $BARE_REPO/hooks/post-receive" "hook: exits cleanly"
run_test "[ -x $BARE_REPO/hooks/post-receive ]" "post-receive hook is executable"

# Config: [core] section exists
run_test "grep -q '^\[core\]' \$BARE_REPO/config" "config file contains '[core]' section"

# Config: sharedRepository = group is set under [core]
run_test "grep -q '^[[:space:]]*sharedRepository = group' \$BARE_REPO/config" "config file sets 'sharedRepository = group' under [core]"

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
