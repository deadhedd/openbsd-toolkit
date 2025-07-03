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
. "$SCRIPT_DIR/../scripts/load-secrets.sh"

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
    repo=$1; desc=$2
    run_test "su - ${REG_USER:-obsidian} -c \"git config --global --get-all safe.directory | grep -q '^$repo\$'\"" "$desc"
  }

  assert_user_shell() {
    user=$1; shell=$2; desc=$3
    run_test "grep -q \"^$user:.*:$shell\$\" /etc/passwd" "$desc"
  }

  #––– Begin Test Plan –––
  echo "1..52"

  # configuration defaults
  REG_USER=${REG_USER:-obsidian}
  GIT_USER=${GIT_USER:-git}
  VAULT=${VAULT:-vault}

  #  1. Packages installed
  run_test "command -v git" \
           "git is installed"

  #  2-5. Users and shells
  run_test "id $REG_USER" \
           "user '$REG_USER' exists"
  assert_user_shell "$REG_USER" "/bin/ksh" \
           "shell for '$REG_USER' is /bin/ksh"
  run_test "id $GIT_USER" \
           "user '$GIT_USER' exists"
  assert_user_shell "$GIT_USER" "/usr/local/bin/git-shell" \
           "shell for '$GIT_USER' is git-shell"

  #  6-10. doas config
  run_test "[ -f /etc/doas.conf ]" \
           "doas.conf exists"
  run_test "grep -q \"^permit persist ${REG_USER} as root\$\" /etc/doas.conf" \
           "doas.conf allows persist ${REG_USER}"
  run_test "grep -q \"^permit nopass ${GIT_USER} as root cmd git\\*\" /etc/doas.conf" \
           "doas.conf allows nopass ${GIT_USER} for git commands"
  run_test "stat -f '%Su:%Sg' /etc/doas.conf | grep -q '^root:wheel\$'" \
           "doas.conf owned by root:wheel"
  assert_file_perm "/etc/doas.conf" "440" \
           "/etc/doas.conf has correct permissions"

  # 11-28 SSH config basics
  run_test "grep -q \"^AllowUsers.*${REG_USER}.*${GIT_USER}\" /etc/ssh/sshd_config" \
           "sshd_config has AllowUsers"
  run_test "pgrep -x sshd >/dev/null" \
           "sshd daemon is running"
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
  run_test "[ -d /home/${REG_USER}/.ssh ]" \
           "ssh directory exists for ${REG_USER}"
  assert_file_perm "/home/${REG_USER}/.ssh" "700" \
           "ssh directory perms for ${REG_USER}"
  run_test "stat -f '%Su:%Sg' /home/${REG_USER}/.ssh | grep -q '^${REG_USER}:${REG_USER}\$'" \
           "ssh directory ownership for ${REG_USER}"
  run_test "[ -d /home/${REG_USER} ]" \
           "home directory for ${REG_USER} exists" 
  run_test "stat -f '%Su' /home/${REG_USER} | grep -q '^${REG_USER}\$'" \
           "${REG_USER} owns their home" 
  
  # New ssh tests:
  # A. Ensure the .ssh directory is present, owned, and has the right perms
  run_test "[ -d /home/${GIT_USER}/.ssh ]"                                            \
         "ssh directory exists for ${GIT_USER}"
  assert_file_perm "/home/${GIT_USER}/.ssh" "700"                                     \
         "ssh directory perms for ${GIT_USER}"
  run_test "stat -f '%Su:%Sg' /home/${GIT_USER}/.ssh | grep -q '^${GIT_USER}:${GIT_USER}\$'" \
         "ssh directory ownership for ${GIT_USER}"

  # B. Ensure authorized_keys is present (or at least mention it) and correct
  run_test "[ -f /home/${GIT_USER}/.ssh/authorized_keys ]"                             \
         "authorized_keys exists for ${GIT_USER}"
  assert_file_perm "/home/${GIT_USER}/.ssh/authorized_keys" "600"                      \
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

  # 33-34 safe.directory config
  # Verify that obsidian (the REG_USER) has whitelisted the BARE repo path
  assert_git_safe "/home/${GIT_USER}/vaults/${VAULT}.git" \
           "safe.directory entry for bare repo '/home/${GIT_USER}/vaults/${VAULT}.git' in ${REG_USER}'s global Git config"

  # Verify that obsidian (the REG_USER) has whitelisted the WORKING‑CLONE path
  assert_git_safe "/home/${REG_USER}/vaults/${VAULT}" \
           "safe.directory entry for working clone '/home/${REG_USER}/vaults/${VAULT}' in ${REG_USER}'s global Git config"

  # 35-39 Post-receive hook config
  run_test "[ -f /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive ]" \
           "post-receive hook exists"
  run_test "grep -q '^#!/bin/sh' /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive" \
           "post-receive hook has correct shebang"
  run_test "grep -q 'git --work-tree=/home/${REG_USER}/vaults/${VAULT} --git-dir=/home/${GIT_USER}/vaults/${VAULT}.git checkout -f' /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive" \
           "post-receive hook content is correct" # this needs manual confirmation
  run_test "stat -f '%Su:%Sg' /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive | \
           grep -q '^${GIT_USER}:${GIT_USER}\$'" "post-receive hook owned by ${GIT_USER}"
  run_test "[ -x /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive ]" \
           "post-receive hook is executable"

  # 40-48. Working clone exists
  run_test "[ -d /home/${REG_USER}/vaults ]" \
           "vaults parent directory exists for ${REG_USER}"
  run_test "stat -f '%Su' /home/${REG_USER}/vaults | grep -q '^${REG_USER}\$'" \
           "/home/${REG_USER}/vaults is owned by ${REG_USER}"
  run_test "su -s /bin/sh - ${REG_USER} -c \"git clone /home/${GIT_USER}/vaults/${VAULT}.git /home/${REG_USER}/vaults/${VAULT}-test-clone \
           && rm -rf /home/${REG_USER}/vaults/${VAULT}-test-clone\"" \
           "working clone can be created by ${REG_USER}"
  run_test "[ -d /home/${REG_USER}/vaults/${VAULT}/.git ]" \
           "working clone exists for '${REG_USER}'"
  # A. Check that the .git directory is there
  run_test "[ -d /home/${REG_USER}/vaults/${VAULT}/.git ]"                             \
         "working clone .git directory exists for ${REG_USER}"
  # B. Check that the remote origin URL matches the bare repo path
  run_test "su - ${REG_USER} -c \"git -C /home/${REG_USER}/vaults/${VAULT} remote get-url origin | \
           grep -q '/home/${GIT_USER}/vaults/${VAULT}.git'\"" "working clone remote origin correct for ${REG_USER}"
  # C. Check there is at least one commit
  run_test "su - ${REG_USER} -c \"git -C /home/${REG_USER}/vaults/${VAULT} log -1 --pretty=%B | \
           grep -q 'initial commit'\"" "initial commit message present in working clone"
  run_test "su - ${REG_USER} -c \"git -C /home/${REG_USER}/vaults/${VAULT} rev-parse HEAD >/dev/null\"" \
           "initial commit present in working clone"
  run_test "[ -f /home/${GIT_USER}/vaults/${VAULT}.git/HEAD ]" \
           "bare repo initialized (HEAD file present)"

  # 49-54 HISTFILE export
  run_test "grep -q '^export HISTFILE=/home/${REG_USER}/\.ksh_history' /home/${REG_USER}/.profile" \
          "${REG_USER} .profile sets HISTFILE to /home/${REG_USER}/.ksh_history"
  run_test "grep -q '^export HISTFILE=/home/${GIT_USER}/\.ksh_history' /home/${GIT_USER}/.profile" \
          "${GIT_USER} .profile sets HISTFILE to /home/${GIT_USER}/.ksh_history"
  run_test "grep -q '^export HISTSIZE=5000' /home/${REG_USER}/.profile" \
          "HISTSIZE set to 5000 for ${REG_USER}"
  run_test "grep -q '^export HISTSIZE=5000' /home/${GIT_USER}/.profile" \
          "HISTSIZE set to 5000 for ${GIT_USER}"
  run_test "grep -q '^export HISTCONTROL=ignoredups' /home/${REG_USER}/.profile" \
          "HISTCONTROL set to ignoredups for ${REG_USER}"
  run_test "grep -q '^export HISTCONTROL=ignoredups' /home/${GIT_USER}/.profile" \
          "HISTCONTROL set to ignoredups for ${GIT_USER}"
           
  # 55-56 Password field handling (no $OBS_PASS/$GIT_PASS → empty; else → non‑empty hash)
  if [ -z "${OBS_PASS:-}" ]; then
    run_test "grep -q \"^${REG_USER}::\" /etc/master.passwd" \
             "password removed for ${REG_USER}"
  else
    run_test "grep -q \"^${REG_USER}:[^:]\+:\" /etc/master.passwd" \
             "password set for ${REG_USER}"
  fi

  if [ -z "${GIT_PASS:-}" ]; then
    run_test "grep -q \"^${GIT_USER}::\" /etc/master.passwd" \
             "password removed for ${GIT_USER}"
  else
    run_test "grep -q \"^${GIT_USER}:[^:]\+:\" /etc/master.passwd" \
             "password set for ${GIT_USER}"
  fi

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

