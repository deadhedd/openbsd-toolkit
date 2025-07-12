#!/bin/sh
#
# test_obsidian_git.sh – Verify git-backed Obsidian sync configuration (with optional logging)
# Usage: ./test_obsidian_git.sh [--log[=FILE]] [-h]
#

set -X

# 1) Locate this script’s directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 2) Logging defaults
FORCE_LOG=0
LOGFILE=""

# 3) Help text
usage() {
    cat <<EOF
Usage: $(basename "$0") [--log[=FILE]] [-h]

  --log, -l       Capture stdout, stderr, and xtrace into:
                    ${SCRIPT_DIR}/logs/$(basename "$0" .sh)-TIMESTAMP.log
                  Or use --log=FILE to choose a custom path.

  -h, --help      Show this help and exit.
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


# 6) Turn on xtrace if you want command tracing in the log
#set -x

# 7) Load secrets
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$PROJECT_ROOT/config/load_secrets.sh"

# 8) Define path variables
OBS_HOME="/home/${OBS_USER}"
BARE_REPO="/home/${GIT_USER}/vaults/${VAULT}.git"

# 9) Test framework
run_tests() {
    local tests=0 fails=0

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
        local path="$1" want="$2" desc="$3"
        run_test "stat -f '%Lp' $path | grep -q '^$want\$'" "$desc"
    }

    assert_git_safe() {
        local repo="$1" desc="$2" user="${3:-${OBS_USER}}"
        local config="/home/$user/.gitconfig"
        run_test \
          "grep -E '^[[:space:]]*safe\.directory[[:space:]]*='\"$repo\"\$\" $config" \
          "$desc"
    }

    assert_user_shell() {
        local user="$1" shell="$2" desc="$3"
        run_test "grep -q \"^$user:.*:$shell\$\" /etc/passwd" "$desc"
    }

    echo "1..49"

    #  1) Git installed
    run_test "command -v git" "git is installed"

    #  2–5) Users and shells
    run_test "id $OBS_USER" "user '$OBS_USER' exists"
    assert_user_shell "$OBS_USER" "/bin/ksh" "shell for '$OBS_USER' is /bin/ksh"
    run_test "id $GIT_USER" "user '$GIT_USER' exists"
    assert_user_shell "$GIT_USER" "/usr/local/bin/git-shell" "shell for '$GIT_USER' is git-shell"

    #  6–10) doas configuration
    run_test "[ -f /etc/doas.conf ]" "doas.conf exists"
    run_test "grep -q \"^permit persist $OBS_USER as root\$\" /etc/doas.conf" "doas.conf allows persist $OBS_USER"
    run_test "grep -q \"^permit nopass $GIT_USER as root cmd git\\*\" /etc/doas.conf" "doas.conf allows nopass $GIT_USER for git commands"
    run_test "stat -f '%Su:%Sg' /etc/doas.conf | grep -q '^root:wheel\$'" "doas.conf owner root:wheel"
    assert_file_perm "/etc/doas.conf" "440" "/etc/doas.conf permissions"

    # 11–28) SSH config basics
    run_test "grep -q \"^AllowUsers.*$OBS_USER.*$GIT_USER\" /etc/ssh/sshd_config" "sshd_config has AllowUsers"
    run_test "pgrep -x sshd >/dev/null" "sshd daemon is running"

    # Home & .ssh for GIT_USER
    run_test "[ -d /home/$GIT_USER ]" "home directory for $GIT_USER exists"
    run_test "stat -f '%Su' /home/$GIT_USER | grep -q '^$GIT_USER\$'" "$GIT_USER owns home"
    run_test "[ -d /home/$GIT_USER/.ssh ]" "ssh dir for $GIT_USER exists"
    assert_file_perm "/home/$GIT_USER/.ssh" "700" "ssh dir perms for $GIT_USER"
    run_test "stat -f '%Su:%Sg' /home/$GIT_USER/.ssh | grep -q '^$GIT_USER:$GIT_USER\$'" "ssh dir owner for $GIT_USER"

    # Home & .ssh for OBS_USER
    run_test "[ -d $OBS_HOME ]" "home directory for $OBS_USER exists"
    run_test "stat -f '%Su' $OBS_HOME | grep -q '^$OBS_USER\$'" "$OBS_USER owns home"
    run_test "[ -d $OBS_HOME/.ssh ]" "ssh dir for $OBS_USER exists"
    assert_file_perm "$OBS_HOME/.ssh" "700" "ssh dir perms for $OBS_USER"
    run_test "stat -f '%Su:%Sg' $OBS_HOME/.ssh | grep -q '^$OBS_USER:$OBS_USER\$'" "ssh dir owner for $OBS_USER"

    # 23–26) Known hosts for OBS_USER
    run_test "[ -f $OBS_HOME/.ssh/known_hosts ]" "known_hosts for $OBS_USER exists"
    run_test "grep -q '$SERVER' $OBS_HOME/.ssh/known_hosts" "known_hosts contains server"
    assert_file_perm "$OBS_HOME/.ssh/known_hosts" "644" "known_hosts perms for $OBS_USER"
    run_test "stat -f '%Su:%Sg' $OBS_HOME/.ssh/known_hosts | grep -q '^$OBS_USER:$OBS_USER\$'" "known_hosts owner for $OBS_USER"

    # 27–28) safe.directory tests for GIT_USER
    assert_git_safe "$BARE_REPO" "safe.directory for bare repo in $GIT_USER config" "$GIT_USER"
    assert_git_safe "/home/$OBS_USER/vaults/$VAULT" "safe.directory for work-tree in $GIT_USER config" "$GIT_USER"

    # 29–31) Authorized keys for GIT_USER
    run_test "[ -f /home/$GIT_USER/.ssh/authorized_keys ]" "authorized_keys for $GIT_USER exists"
    assert_file_perm "/home/$GIT_USER/.ssh/authorized_keys" "600" "authorized_keys perms for $GIT_USER"
    run_test "stat -f '%Su:%Sg' /home/$GIT_USER/.ssh/authorized_keys | grep -q '^$GIT_USER:$GIT_USER\$'" "authorized_keys owner for $GIT_USER"

    # 32–35) Bare repo config
    run_test "[ -d /home/$GIT_USER/vaults ]" "vaults dir exists for $GIT_USER"
    run_test "[ -d /home/$GIT_USER/vaults/$VAULT.git ]" "bare repo exists"
    run_test "stat -f '%Su' /home/$GIT_USER/vaults/$VAULT.git | grep -q '^$GIT_USER\$'" "bare repo owner $GIT_USER"
    run_test "[ -f /home/$GIT_USER/vaults/$VAULT.git/HEAD ]" "bare repo HEAD present"

    # 36) safe.directory for OBS_USER
    assert_git_safe "/home/$OBS_USER/vaults/$VAULT" "safe.directory for working clone in $OBS_USER config"

    # 37–41) Post-receive hook
    run_test "[ -f /home/$GIT_USER/vaults/$VAULT.git/hooks/post-receive ]" "post-receive hook exists"
    run_test "grep -q '^#!/bin/sh' /home/$GIT_USER/vaults/$VAULT.git/hooks/post-receive" "hook shebang correct"
    run_test "grep -q 'git --work-tree=/home/$OBS_USER/vaults/$VAULT --git-dir=$BARE_REPO checkout -f' /home/$GIT_USER/vaults/$VAULT.git/hooks/post-receive" "hook content correct"
    run_test "stat -f '%Su:%Sg' /home/$GIT_USER/vaults/$VAULT.git/hooks/post-receive | grep -q '^$GIT_USER:$GIT_USER\$'" "hook owner correct"
    run_test "[ -x /home/$GIT_USER/vaults/$VAULT.git/hooks/post-receive ]" "hook executable"

    # 42–49) Working clone checks
    run_test "[ -d $OBS_HOME/vaults ]" "vaults dir exists for $OBS_USER"
    run_test "stat -f '%Su' $OBS_HOME/vaults | grep -q '^$OBS_USER\$'" "vaults owner $OBS_USER"
    run_test "su - $OBS_USER -c \"git -C $OBS_HOME/vaults/$VAULT remote get-url origin | grep -q '$BARE_REPO'\"" "working clone origin correct"
    run_test "su - $OBS_USER -c \"git -C $OBS_HOME/vaults/$VAULT log -1 --pretty=%B | grep -q 'initial commit'\"" "initial commit present"
    run_test "su - $OBS_USER -c \"git -C $OBS_HOME/vaults/$VAULT rev-parse HEAD >/dev/null\"" "initial commit hash present"
    run_test "[ -f $BARE_REPO/HEAD ]" "bare repo HEAD present"

    echo ""
    if [ "$fails" -eq 0 ]; then
        echo "✅ All $tests tests passed."
    else
        echo "❌ $fails of $tests tests failed."
    fi

    return $fails
}

# 10) Wrapper to capture output and optionally log
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

# 11) Execute
run_and_maybe_log

