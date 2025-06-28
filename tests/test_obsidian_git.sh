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
  echo "1..32"

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

  #  6-9. doas config
  assert_file_perm "/etc/doas.conf" "440"                                             "/etc/doas.conf has correct permissions"
  run_test "stat -f '%Su:%Sg' /etc/doas.conf | grep -q '^root:wheel\$'"               "doas.conf owned by root:wheel"
  run_test "grep -q \"^permit persist ${REG_USER} as root\$\" /etc/doas.conf"        "doas.conf allows persist ${REG_USER}"
  run_test "grep -q \"^permit nopass ${GIT_USER} as root cmd git\\*\" /etc/doas.conf" \
           "doas.conf allows nopass ${GIT_USER} for git commands"

  # 10-14 SSH config basics
  run_test "[ -d /home/${REG_USER} ]"                                                 "home directory for ${REG_USER} exists"
  run_test "stat -f '%Su' /home/${REG_USER} | grep -q '^${REG_USER}\$'"               "${REG_USER} owns their home"
  run_test "[ -d /home/${GIT_USER} ]"                                                 "home directory for ${GIT_USER} exists"
  run_test "stat -f '%Su' /home/${GIT_USER} | grep -q '^${GIT_USER}\$'"               "${GIT_USER} owns their home"
  run_test "grep -q \"^AllowUsers.*${REG_USER}.*${GIT_USER}\" /etc/ssh/sshd_config"   "sshd_config has AllowUsers"

  # 15-16 Bare repo config
  run_test "[ -d /home/${GIT_USER}/vaults/${VAULT}.git ]"                              "bare repo exists"
  run_test "stat -f '%Su' /home/${GIT_USER}/vaults/${VAULT}.git | grep -q '^${GIT_USER}\$'" \
           "bare repo is owned by '${GIT_USER}'"

  # 17-18 Post-receive hook config
  run_test "[ -x /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive ]"            "post-receive hook is executable"
  run_test "stat -f '%Su:%Sg' /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive | grep -q '^${GIT_USER}:${GIT_USER}\$'" \
           "post-receive hook owned by ${GIT_USER}"

  # 19. Bare repo HEAD
  run_test "[ -f /home/${GIT_USER}/vaults/${VAULT}.git/HEAD ]"                         "bare repo HEAD exists"

  # 20. Working clone exists
  run_test "[ -d /home/${REG_USER}/vaults/${VAULT}/.git ]"                             "working clone exists for '${REG_USER}'"

  # 21. Safe.directory for working clone
  assert_git_safe "/home/${REG_USER}/vaults/${VAULT}"                                  "safe.directory configured for working clone"

  # 22-23 HISTFILE export
  run_test "grep -q '^export HISTFILE=\\\\\$HOME/.histfile' /home/${REG_USER}/.profile" "${REG_USER} .profile sets HISTFILE"
  run_test "grep -q '^export HISTFILE=\\\\\$HOME/.histfile' /home/${GIT_USER}/.profile" "${GIT_USER} .profile sets HISTFILE"

  # — Newly added tests —

  # 24-25 Password field removed
  run_test "grep -q \"^${REG_USER}::\" /etc/master.passwd"                              "password removed for ${REG_USER}"
  run_test "grep -q \"^${GIT_USER}::\" /etc/master.passwd"                              "password removed for ${GIT_USER}"

  # 26-28 .ssh directory for git user
  run_test "[ -d /home/${GIT_USER}/.ssh ]"                                              "ssh dir for ${GIT_USER} exists"
  assert_file_perm "/home/${GIT_USER}/.ssh" "700"                                       "ssh dir perm for ${GIT_USER}"
  run_test "stat -f '%Su:%Sg' /home/${GIT_USER}/.ssh | grep -q '^${GIT_USER}:${GIT_USER}\$'" \
           "ssh dir owner for ${GIT_USER}"

  # 29 Safe.directory for bare repo path
  assert_git_safe "/home/${GIT_USER}/vaults/${VAULT}.git"                               "safe.directory configured for bare repo"

  # 30 Initial commit in working clone
  run_test "su - ${REG_USER} -c \"git -C /home/${REG_USER}/vaults/${VAULT} rev-parse HEAD >/dev/null\"" \
           "initial commit present in working clone"

  # 31-32 touch $HISTFILE in profiles
  run_test "grep -q '^touch \\\\\\$HISTFILE' /home/${REG_USER}/.profile"                "touch command in ${REG_USER} .profile"
  run_test "grep -q '^touch \\\\\\$HISTFILE' /home/${GIT_USER}/.profile"                "touch command in ${GIT_USER} .profile"

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

