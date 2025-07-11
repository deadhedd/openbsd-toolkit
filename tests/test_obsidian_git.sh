#!/bin/sh
#
# test_obsidian_git.sh – Verify git-backed Obsidian sync configuration (with optional logging)
#

# 1) Locate this script’s directory so logs always end up alongside it
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGDIR="$SCRIPT_DIR/logs"
mkdir -p "$LOGDIR"

# 2) Defaults: only write a log on failure unless --log is passed
FORCE_LOG=0
LOGFILE=""

#--- Load secrets ---
# 1) Locate this script’s directory
SCRIPT_DIR="$(cd "$(dirname -- "$0")" && pwd)"

# 2) Compute project root (one level up from this script)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 3) Source the loader from the config folder by absolute path
. "$PROJECT_ROOT/config/load_secrets.sh"

#––– Define only the two path variables we need –––
OBS_HOME="/home/${OBS_USER}"
BARE_REPO="/home/${GIT_USER}/vaults/${VAULT}.git"

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

# 4) Parse command-line flags
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
  repo=$1
  desc=$2
  user=${3:-${OBS_USER:-obsidian}}
  config="/home/${user}/.gitconfig"
  run_test "grep -E '^[[:space:]]*directory[[:space:]]*=[[:space:]]*${repo}$' \"$config\"" "$desc"
}


  assert_user_shell() {
    user=$1; shell=$2; desc=$3
    run_test "grep -q \"^$user:.*:$shell\$\" /etc/passwd" "$desc"
  }

  #––– Begin Test Plan –––
  echo "1..56"

  #  1. Packages installed
  run_test "command -v git" \
           "git is installed"

  #  2-5. Users and shells
  run_test "id $OBS_USER" \
           "user '$OBS_USER' exists"
  assert_user_shell "$OBS_USER" "/bin/ksh" \
           "shell for '$OBS_USER' is /bin/ksh"
  run_test "id $GIT_USER" \
           "user '$GIT_USER' exists"
  assert_user_shell "$GIT_USER" "/usr/local/bin/git-shell" \
           "shell for '$GIT_USER' is git-shell"

  #  6-10. doas config
  run_test "[ -f /etc/doas.conf ]" \
           "doas.conf exists"
  run_test "grep -q \"^permit persist ${OBS_USER} as root\$\" /etc/doas.conf" \
           "doas.conf allows persist ${OBS_USER}"
  run_test "grep -q \"^permit nopass ${GIT_USER} as root cmd git\\*\" /etc/doas.conf" \
           "doas.conf allows nopass ${GIT_USER} for git commands"
  run_test "stat -f '%Su:%Sg' /etc/doas.conf | grep -q '^root:wheel\$'" \
           "doas.conf owned by root:wheel"
  assert_file_perm "/etc/doas.conf" "440" \
           "/etc/doas.conf has correct permissions"

  # 11-28 SSH config basics
  run_test "grep -q \"^AllowUsers.*${OBS_USER}.*${GIT_USER}\" /etc/ssh/sshd_config" \
           "sshd_config has AllowUsers"
  run_test "pgrep -x sshd >/dev/null" \
           "sshd daemon is running"

  # home & .ssh for GIT_USER
  run_test "[ -d /home/${GIT_USER} ]" \
           "home directory for ${GIT_USER} exists"
  run_test "stat -f '%Su' /home/${GIT_USER} | grep -q '^${GIT_USER}\$'" \
           "${GIT_USER} owns their home"
  run_test "[ -d /home/${GIT_USER}/.ssh ]" \
           "ssh dir for ${GIT_USER} exists"
  assert_file_perm "/home/${GIT_USER}/.ssh" "700" \
           "ssh dir perm for ${GIT_USER}"
  run_test "stat -f '%Su:%Sg' /home/${GIT_USER}/.ssh | grep -q '^${GIT_USER}:${GIT_USER}\$'" \
           "ssh dir owner for ${GIT_USER}"

  # home & .ssh for OBS_USER
  run_test "[ -d ${OBS_HOME} ]" \
           "home directory for ${OBS_USER} exists"
  run_test "stat -f '%Su' ${OBS_HOME} | grep -q '^${OBS_USER}\$'" \
           "${OBS_USER} owns their home"
  run_test "[ -d ${OBS_HOME}/.ssh ]" \
           "ssh directory exists for ${OBS_USER}"
  assert_file_perm "${OBS_HOME}/.ssh" "700" \
           "ssh directory perms for ${OBS_USER}"
  run_test "stat -f '%Su:%Sg' ${OBS_HOME}/.ssh | grep -q '^${OBS_USER}:${OBS_USER}\$'" \
           "ssh directory ownership for ${OBS_USER}"

  #––– NEW OBS_USER known_hosts tests –––
  run_test "[ -f ${OBS_HOME}/.ssh/known_hosts ]" \
           "known_hosts file exists for ${OBS_USER}"
  run_test "grep -q '${SERVER}' ${OBS_HOME}/.ssh/known_hosts" \
           "known_hosts contains server entry for ${OBS_USER}"
  assert_file_perm "${OBS_HOME}/.ssh/known_hosts" "644" \
           "known_hosts perms for ${OBS_USER}"
  run_test "stat -f '%Su:%Sg' ${OBS_HOME}/.ssh/known_hosts | grep -q '^${OBS_USER}:${OBS_USER}\$'" \
           "known_hosts owned by ${OBS_USER}"

  #––– NEW GIT_USER safe.directory test –––
assert_git_safe "${BARE_REPO}" \
  "safe.directory entry for bare repo in ${GIT_USER}'s global Git config" \
  "${GIT_USER}"

assert_git_safe "/home/${OBS_USER}/vaults/${VAULT}" \
  "safe.directory entry for work-tree in ${GIT_USER}'s global Git config" \
  "${GIT_USER}"

  #––– existing GIT_USER authorized_keys tests –––
  run_test "[ -f /home/${GIT_USER}/.ssh/authorized_keys ]" \
           "authorized_keys exists for ${GIT_USER}"
  assert_file_perm "/home/${GIT_USER}/.ssh/authorized_keys" "600" \
           "authorized_keys perms for ${GIT_USER}"
  run_test "stat -f '%Su:%Sg' /home/${GIT_USER}/.ssh/authorized_keys | grep -q '^${GIT_USER}:${GIT_USER}\$'" \
           "authorized_keys ownership for ${GIT_USER}"

  # 29-32 Bare repo config
  run_test "[ -d /home/${GIT_USER}/vaults ]" \
           "vaults parent directory exists for ${GIT_USER}"
  run_test "[ -d /home/${GIT_USER}/vaults/${VAULT}.git ]" \
           "bare repo exists"
  run_test "stat -f '%Su' /home/${GIT_USER}/vaults/${VAULT}.git | grep -q '^${GIT_USER}\$'" \
           "bare repo is owned by '${GIT_USER}'"
  run_test "[ -f /home/${GIT_USER}/vaults/${VAULT}.git/HEAD ]" \
           "bare repo initialized (HEAD file present)"

  # 33-34 safe.directory config for OBS_USER
assert_git_safe "/home/${OBS_USER}/vaults/${VAULT}" \
  "safe.directory entry for working clone in ${OBS_USER}'s global Git config"

  # 35-39 Post-receive hook config
  run_test "[ -f /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive ]" \
           "post-receive hook exists"
  run_test "grep -q '^#!/bin/sh' /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive" \
           "post-receive hook has correct shebang"
  run_test "grep -q 'git --work-tree=/home/${OBS_USER}/vaults/${VAULT} --git-dir=${BARE_REPO} checkout -f' /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive" \
           "post-receive hook content is correct"
  run_test "stat -f '%Su:%Sg' /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive | grep -q '^${GIT_USER}:${GIT_USER}\$'" \
           "post-receive hook owned by ${GIT_USER}"
  run_test "[ -x /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive ]" \
           "post-receive hook is executable"

  # 40-48. Working clone exists
  run_test "[ -d ${OBS_HOME}/vaults ]" \
           "vaults parent directory exists for ${OBS_USER}"
  run_test "stat -f '%Su' ${OBS_HOME}/vaults | grep -q '^${OBS_USER}\$'" \
           "/home/${OBS_USER}/vaults is owned by ${OBS_USER}"
  run_test "[ -r \"${BARE_REPO}/config\" ] && [ -x \"${BARE_REPO}\" ] && [ -w \"${OBS_HOME}/vaults\" ]" \
           "working clone can be created by ${OBS_USER}"
  run_test "[ -d ${OBS_HOME}/vaults/${VAULT}/.git ]" \
           "working clone exists for '${OBS_USER}'"
  run_test "[ -d ${OBS_HOME}/vaults/${VAULT}/.git ]" \
           "working clone .git directory exists for ${OBS_USER}"
  run_test "su - ${OBS_USER} -c \"git -C ${OBS_HOME}/vaults/${VAULT} remote get-url origin | grep -q '${BARE_REPO}'\"" \
           "working clone remote origin correct for ${OBS_USER}"
  run_test "su - ${OBS_USER} -c \"git -C ${OBS_HOME}/vaults/${VAULT} log -1 --pretty=%B | grep -q 'initial commit'\"" \
           "initial commit message present in working clone"
  run_test "su - ${OBS_USER} -c \"git -C ${OBS_HOME}/vaults/${VAULT} rev-parse HEAD >/dev/null\"" \
           "initial commit present in working clone"
  run_test "[ -f ${BARE_REPO}/HEAD ]" \
           "bare repo initialized (HEAD file present)"

  # 49-54 HISTFILE export
  run_test "grep -q '^export HISTFILE=${OBS_HOME}/\.ksh_history' ${OBS_HOME}/.profile" \
           "${OBS_USER} .profile sets HISTFILE correctly"
  run_test "grep -q '^export HISTFILE=/home/${GIT_USER}/\.ksh_history' /home/${GIT_USER}/.profile" \
           "${GIT_USER} .profile sets HISTFILE correctly"
  run_test "grep -q '^export HISTSIZE=5000' ${OBS_HOME}/.profile" \
           "HISTSIZE set to 5000 for ${OBS_USER}"
  run_test "grep -q '^export HISTSIZE=5000' /home/${GIT_USER}/.profile" \
           "HISTSIZE set to 5000 for ${GIT_USER}"
  run_test "grep -q '^export HISTCONTROL=ignoredups' ${OBS_HOME}/.profile" \
           "HISTCONTROL set to ignoredups for ${OBS_USER}"
  run_test "grep -q '^export HISTCONTROL=ignoredups' /home/${GIT_USER}/.profile" \
           "HISTCONTROL set to ignoredups for ${GIT_USER}"

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

