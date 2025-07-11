#!/bin/sh
#
# test_obsidian_git.sh – Verify git‑backed Obsidian sync configuration (with optional logging)
#

# 1) Locate this script’s directory & set up logging
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGDIR="$SCRIPT_DIR/logs"
mkdir -p "$LOGDIR"

# 2) Set logging defaults
FORCE_LOG=0
LOGFILE=""

# 3) Load secrets
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$PROJECT_ROOT/config/load_secrets.sh"

# 4) Define path variables
OBS_HOME="/home/${OBS_USER}"
BARE_REPO="/home/${GIT_USER}/vaults/${VAULT}.git"

# 5) Usage helper
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

# 6) Parse command‑line flags
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

# 7) Build default log filename if needed
if [ "$FORCE_LOG" -eq 1 ] && [ -z "$LOGFILE" ]; then
    LOGFILE="$LOGDIR/$(basename "$0" .sh)-$(date +%Y%m%d_%H%M%S).log"
fi

# 8) Test framework
run_tests() {
    local tests=0 fails=0

    # Helper to run a single test
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

    # Assert file permissions
    assert_file_perm() {
        local path="$1" want="$2" desc="$3"
        run_test "stat -f '%Lp' \$path | grep -q '^$want\$'" "$desc"
    }

    # Assert safe.directory in Git config
    assert_git_safe() {
        local repo="$1" desc="$2" user="${3:-${OBS_USER:-obsidian}}"
        local config="/home/\$user/.gitconfig"
        run_test "grep -E '^[[:space:]]*directory[[:space:]]*=[[:space:]]*$repo\$' \"\$config\"" "$desc"
    }

    # Assert user shell in /etc/passwd
    assert_user_shell() {
        local user="$1" shell="$2" desc="$3"
        run_test "grep -q \"^$user:.*:$shell\$\" /etc/passwd" "$desc"
    }

    echo "1..49"

    #  1) Git installed
    run_test "command -v git" "git is installed"

    #  2–5) Users and shells
    run_test "id \$OBS_USER" "user '\$OBS_USER' exists"
    assert_user_shell "\$OBS_USER" "/bin/ksh" "shell for '\$OBS_USER' is /bin/ksh"
    run_test "id \$GIT_USER" "user '\$GIT_USER' exists"
    assert_user_shell "\$GIT_USER" "/usr/local/bin/git-shell" "shell for '\$GIT_USER' is git-shell"

    #  6–10) doas configuration
    run_test "[ -f /etc/doas.conf ]" "doas.conf exists"
    run_test "grep -q \"^permit persist \$OBS_USER as root\$\" /etc/doas.conf" "doas.conf allows persist \$OBS_USER"
    run_test "grep -q \"^permit nopass \$GIT_USER as root cmd git\\*\" /etc/doas.conf" "doas.conf allows nopass \$GIT_USER for git commands"
    run_test "stat -f '%Su:%Sg' /etc/doas.conf | grep -q '^root:wheel\$'" "doas.conf owned by root:wheel"
    assert_file_perm "/etc/doas.conf" "440" "/etc/doas.conf has correct permissions"

    # 11–28) SSH config basics
    run_test "grep -q \"^AllowUsers.*\$OBS_USER.*\$GIT_USER\" /etc/ssh/sshd_config" "sshd_config has AllowUsers"
    run_test "pgrep -x sshd >/dev/null" "sshd daemon is running"

    # Home & .ssh for GIT_USER
    run_test "[ -d /home/\$GIT_USER ]" "home directory for \$GIT_USER exists"
    run_test "stat -f '%Su' /home/\$GIT_USER | grep -q '^\$GIT_USER\$'" "\$GIT_USER owns their home"
    run_test "[ -d /home/\$GIT_USER/.ssh ]" "ssh dir for \$GIT_USER exists"
    assert_file_perm "/home/\$GIT_USER/.ssh" "700" "ssh dir permissions for \$GIT_USER"
    run_test "stat -f '%Su:%Sg' /home/\$GIT_USER/.ssh | grep -q '^\$GIT_USER:\$GIT_USER\$'" "ssh dir owner for \$GIT_USER"

    # Home & .ssh for OBS_USER
    run_test "[ -d \$OBS_HOME ]" "home directory for \$OBS_USER exists"
    run_test "stat -f '%Su' \$OBS_HOME | grep -q '^\$OBS_USER\$'" "\$OBS_USER owns their home"
    run_test "[ -d \$OBS_HOME/.ssh ]" "ssh directory exists for \$OBS_USER"
    assert_file_perm "\$OBS_HOME/.ssh" "700" "ssh directory permissions for \$OBS_USER"
    run_test "stat -f '%Su:%Sg' \$OBS_HOME/.ssh | grep -q '^\$OBS_USER:\$OBS_USER\$'" "ssh directory ownership for \$OBS_USER"

    # 23–26) Known hosts for OBS_USER
    run_test "[ -f \$OBS_HOME/.ssh/known_hosts ]" "known_hosts file exists for \$OBS_USER"
    run_test "grep -q '\$SERVER' \$OBS_HOME/.ssh/known_hosts" "known_hosts contains server entry"
    assert_file_perm "\$OBS_HOME/.ssh/known_hosts" "644" "known_hosts permissions for \$OBS_USER"
    run_test "stat -f '%Su:%Sg' \$OBS_HOME/.ssh/known_hosts | grep -q '^\$OBS_USER:\$OBS_USER\$'" "known_hosts owner for \$OBS_USER"

    # 27–28) safe.directory tests for GIT_USER
    assert_git_safe "\$BARE_REPO" "safe.directory entry for bare repo in \$GIT_USER's global config" "\$GIT_USER"
    assert_git_safe "/home/\$OBS_USER/vaults/\$VAULT" "safe.directory entry for work-tree in \$GIT_USER's global config" "\$GIT_USER"

    # 29–31) Authorized keys for GIT_USER
    run_test "[ -f /home/\$GIT_USER/.ssh/authorized_keys ]" "authorized_keys exists for \$GIT_USER"
    assert_file_perm "/home/\$GIT_USER/.ssh/authorized_keys" "600" "authorized_keys permissions for \$GIT_USER"
    run_test "stat -f '%Su:%Sg' /home/\$GIT_USER/.ssh/authorized_keys | grep -q '^\$GIT_USER:\$GIT_USER\$'" "authorized_keys ownership for \$GIT_USER"

    # 32–35) Bare repo configuration
    run_test "[ -d /home/\$GIT_USER/vaults ]" "vaults parent directory exists for \$GIT_USER"
    run_test "[ -d /home/\$GIT_USER/vaults/\$VAULT.git ]" "bare repo exists"
    run_test "stat -f '%Su' /home/\$GIT_USER/vaults/\$VAULT.git | grep -q '^\$GIT_USER\$'" "bare repo owned by \$GIT_USER"
    run_test "[ -f /home/\$GIT_USER/vaults/\$VAULT.git/HEAD ]" "bare repo initialized (HEAD present)"

    # 36) safe.directory for OBS_USER
    assert_git_safe "/home/\$OBS_USER/vaults/\$VAULT" "safe.directory for working clone in \$OBS_USER's global config"

    # 37–41) Post-receive hook configuration
    run_test "[ -f /home/\$GIT_USER/vaults/\$VAULT.git/hooks/post-receive ]" "post-receive hook exists"
    run_test "grep -q '^#!/bin/sh' /home/\$GIT_USER/vaults/\$VAULT.git/hooks/post-receive" "post-receive hook shebang correct"
    run_test "grep -q 'git --work-tree=/home/\$OBS_USER/vaults/\$VAULT --git-dir=\$BARE_REPO checkout -f' /home/\$GIT_USER/vaults/\$VAULT.git/hooks/post-receive" "post-receive hook content correct"
    run_test "stat -f '%Su:%Sg' /home/\$GIT_USER/vaults/\$VAULT.git/hooks/post-receive | grep -q '^\$GIT_USER:\$GIT_USER\$'" "post-receive hook ownership correct"
    run_test "[ -x /home/\$GIT_USER/vaults/\$VAULT.git/hooks/post-receive ]" "post-receive hook executable"

    # 42–49) Working clone checks
    run_test "[ -d \$OBS_HOME/vaults ]" "vaults parent directory exists for \$OBS_USER"
    run_test "stat -f '%Su' \$OBS_HOME/vaults | grep -q '^\$OBS_USER\$'" "/home/\$OBS_USER/vaults owned by \$OBS_USER"
    run_test "[ -r \"\$BARE_REPO/config\" ] && [ -w \"\$OBS_HOME/vaults\" ]" "working clone can be created by \$OBS_USER"
    run_test "[ -d \$OBS_HOME/vaults/\$VAULT/.git ]" "working clone exists"
    run_test "su - \$OBS_USER -c \"git -C \$OBS_HOME/vaults/\$VAULT remote get-url origin | grep -q '\$BARE_REPO'\"" "working clone remote origin correct"
    run_test "su - \$OBS_USER -c \"git -C \$OBS_HOME/vaults/\$VAULT log -1 --pretty=%B | grep -q 'initial commit'\"" "initial commit message present"
    run_test "su - \$OBS_USER -c \"git -C \$OBS_HOME/vaults/\$VAULT rev-parse HEAD >/dev/null\"" "initial commit present"
    run_test "[ -f \$BARE_REPO/HEAD ]" "bare repo HEAD present"

    # Summary
    echo ""
    if [ "$fails" -eq 0 ]; then
        echo "✅ All $tests tests passed."
    else
        echo "❌ $fails of $tests tests failed."
    fi

    return $fails
}

# 9) Wrapper to capture output and optionally log
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

# 10) Execute
run_and_maybe_log

