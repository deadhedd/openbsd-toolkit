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
  echo "1..46"

  # configuration defaults
  REG_USER=${REG_USER:-obsidian}
  GIT_USER=${GIT_USER:-git}
  VAULT=${VAULT:-vault}

  #  1. Packages installed
  run_test "command -v git"                                                          "git is installed"

  #  2-5. Users and shells
  run_test "id $REG_USER"                                                            "user '$REG_USER' exists"
  assert_user_shell "$REG_USER" "/bin/ksh"                                           "shell for '$REG_USER' is /bin/ksh"
  run_test "id $GIT_USER"                                                            "user '$GIT_USER' exists"
  assert_user_shell "$GIT_USER" "/usr/local/bin/git-shell"                           "shell for '$GIT_USER' is git-shell"

  #  6-10. doas config
  # TEST: DOAS.CONF EXISTS
  run_test "grep -q \"^permit persist ${REG_USER} as root\$\" /etc/doas.conf"        "doas.conf allows persist ${REG_USER}"
  run_test "grep -q \"^permit nopass ${GIT_USER} as root cmd git\\*\" /etc/doas.conf" \
           "doas.conf allows nopass ${GIT_USER} for git commands"
  run_test "stat -f '%Su:%Sg' /etc/doas.conf | grep -q '^root:wheel\$'"               "doas.conf owned by root:wheel"
  assert_file_perm "/etc/doas.conf" "440"                                             "/etc/doas.conf has correct permissions"

  # 11-20 SSH config basics
  run_test "grep -q \"^AllowUsers.*${REG_USER}.*${GIT_USER}\" /etc/ssh/sshd_config"   "sshd_config has AllowUsers"
  # TEST: SSHD RUNNING
  run_test "[ -d /home/${GIT_USER} ]"                                                 "home directory for ${GIT_USER} exists"
  run_test "stat -f '%Su' /home/${GIT_USER} | grep -q '^${GIT_USER}\$'"               "${GIT_USER} owns their home"
  run_test "[ -d /home/${GIT_USER}/.ssh ]"                                              "ssh dir for ${GIT_USER} exists"
  assert_file_perm "/home/${GIT_USER}/.ssh" "700"                                       "ssh dir perm for ${GIT_USER}"
  run_test "stat -f '%Su:%Sg' /home/${GIT_USER}/.ssh | grep -q '^${GIT_USER}:${GIT_USER}\$'" \
           "ssh dir owner for ${GIT_USER}"
  # TEST: ${REG_USER}/.SSH THINGS AS ABOVE
  run_test "[ -d /home/${REG_USER} ]"                                                 "home directory for ${REG_USER} exists" 
  run_test "stat -f '%Su' /home/${REG_USER} | grep -q '^${REG_USER}\$'"               "${REG_USER} owns their home" 
  
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


  # 21-24 Bare repo config
  # TEST: /home/${GIT_USER}/vaults EXISTS
  run_test "[ -d /home/${GIT_USER}/vaults/${VAULT}.git ]"                             "bare repo exists"
  run_test "stat -f '%Su' /home/${GIT_USER}/vaults/${VAULT}.git | grep -q '^${GIT_USER}\$'" \
           "bare repo is owned by '${GIT_USER}'"
  run_test "[ -f /home/${GIT_USER}/vaults/${VAULT}.git/HEAD ]"                         "bare repo initialized (HEAD file present)"

  # 25-26
  # TEST: SAFE.DIRECTORY FOR VAULT
  # Verify that obsidian (the REG_USER) has whitelisted the BARE repo path
assert_git_safe "/home/${GIT_USER}/vaults/${VAULT}.git" \
  "safe.directory entry for bare repo '/home/${GIT_USER}/vaults/${VAULT}.git' in ${REG_USER}'s global Git config"

# Verify that obsidian (the REG_USER) has whitelisted the WORKING‑CLONE path
assert_git_safe "/home/${REG_USER}/vaults/${VAULT}" \
  "safe.directory entry for working clone '/home/${REG_USER}/vaults/${VAULT}' in ${REG_USER}'s global Git config"
                               "safe.directory configured for bare repo"

  # 27-30 Post-receive hook config
  # TEST: POST-RECIEVE EXISTS
  # TEST: POST-RECIEVE CONTENT IS CORRECT
  run_test "stat -f '%Su:%Sg' /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive | grep -q '^${GIT_USER}:${GIT_USER}\$'" \
           "post-receive hook owned by ${GIT_USER}"
  run_test "[ -x /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive ]"            "post-receive hook is executable"

  # 31-34. Working clone exists
  # TEST /home/${REG_USER}/vaults EXISTS
  # TEST /home/${REG_USER}/vaults HAS CORRECT OWNERSHIP
  # TEST: working clone exists "su -s /bin/sh - ${REG_USER} -c "git clone /home/${GIT_USER}/vaults/${VAULT}.git /home/${REG_USER}/vaults/${VAULT}"" "Working clone exists"
  run_test "[ -d /home/${REG_USER}/vaults/${VAULT}/.git ]"                             "working clone exists for '${REG_USER}'"
  # A. Check that the .git directory is there
run_test "[ -d /home/${REG_USER}/vaults/${VAULT}/.git ]"                             \
         "working clone .git directory exists for ${REG_USER}"

# B. Check that the remote origin URL matches the bare repo path
run_test "su - ${REG_USER} -c \"git -C /home/${REG_USER}/vaults/${VAULT} remote get-url origin | grep -q '/home/${GIT_USER}/vaults/${VAULT}.git'\"" \
         "working clone remote origin correct for ${REG_USER}"

# C. Check there is at least one commit (you already have this, but stated explicitly)
run_test "su - ${REG_USER} -c \"git -C /home/${REG_USER}/vaults/${VAULT} log -1 --pretty=%B | grep -q 'initial commit'\"" \
         "initial commit message present in working clone"


  # 35
  run_test "su - ${REG_USER} -c \"git -C /home/${REG_USER}/vaults/${VAULT} rev-parse HEAD >/dev/null\"" \
           "initial commit present in working clone"

  # 37. Bare repo HEAD
  run_test "[ -f /home/${GIT_USER}/vaults/${VAULT}.git/HEAD ]"                         "bare repo initialized (HEAD file present)"

  # 38-44 HISTFILE export
  run_test "grep -q '^export HISTFILE=\\\\\$HOME/.histfile' /home/${REG_USER}/.profile" "${REG_USER} .profile sets HISTFILE"
  run_test "grep -q '^export HISTFILE=\\\\\$HOME/.histfile' /home/${GIT_USER}/.profile" "${GIT_USER} .profile sets HISTFILE"
  run_test "grep -q '^touch \\\\\\$HISTFILE' /home/${REG_USER}/.profile"                "touch command in ${REG_USER} .profile"
  run_test "grep -q '^touch \\\\\\$HISTFILE' /home/${GIT_USER}/.profile"                "touch command in ${GIT_USER} .profile"
  # TEST: GIT USER HISTORY LENGTH 5000
  # TEST: REG USER HISTORY LENGTH 5000

  # 45-46 Password field handling (no $OBS_PASS/$GIT_PASS → empty; else → non‑empty hash)
  if [ -z "${OBS_PASS:-}" ]; then
    run_test "grep -q \"^${REG_USER}::\" /etc/master.passwd"                            "password removed for ${REG_USER}"
  else
    run_test "grep -q \"^${REG_USER}:[^:]\+:\" /etc/master.passwd"                      "password set for ${REG_USER}"
  fi

  if [ -z "${GIT_PASS:-}" ]; then
    run_test "grep -q \"^${GIT_USER}::\" /etc/master.passwd"                            "password removed for ${GIT_USER}"
  else
    run_test "grep -q \"^${GIT_USER}:[^:]\+:\" /etc/master.passwd"                      "password set for ${GIT_USER}"
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

