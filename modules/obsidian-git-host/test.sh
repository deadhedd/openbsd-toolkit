#!/bin/sh
#
# modules/obsidian-git-host/test.sh — Verify Obsidian vault sync configuration
# Author: deadhedd
# Version: 1.0.0
# Updated: 2025-08-02
#
# Usage: sh test.sh [--log[=FILE]] [--debug[=FILE]] [-h]
#
# Description:
#   Runs TAP-style checks against the Obsidian Git host setup: users/groups,
#   doas and SSH hardening, bare repo & working clone, post-receive hook, git
#   configs (safe.directory/sharedRepository), perms, and history settings.
#
# Deployment considerations:
#   Assumes OBS_USER, GIT_USER, VAULT, and GIT_SERVER are exported (via
#   config/load-secrets.sh). setup.sh is not required to run this test, but most
#   checks will fail unless it (or equivalent steps) has been completed.
#
# Security note:
#   Enabling the --debug flag will log all executed commands (via `set -x`).
#   Setup scripts still log expanded values via `set -vx`, which may expose
#   exported secrets or credentials. Use caution when sharing or retaining
#   debug logs.
#
# See also:
#   - modules/obsidian-git-host/setup.sh
#   - logs/logging.sh
#   - config/load-secrets.sh

##############################################################################
# 0) Resolve paths
##############################################################################

case "$0" in
  */*) SCRIPT_PATH="$0";;
  *)   SCRIPT_PATH="$PWD/$0";;
esac
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
export PROJECT_ROOT

##############################################################################
# 1) Help & banned flags prescan
##############################################################################

show_help() {
  cat <<EOF
  Usage: sh $(basename "$0") [options]

  Description:
    Validate Obsidian vault sync setup on the Git host

  Options:
    -h, --help        Show this help message and exit
    -d, --debug       Enable debug mode (use --debug=FILE for custom file)
    -l, --log         Force log output (use --log=FILE for custom file)
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) show_help; exit 0 ;;
  esac
done

##############################################################################
# 2) Parse flags and initialize logging
##############################################################################

. "$PROJECT_ROOT/logs/logging.sh"
start_logging "$SCRIPT_PATH" "$@"

##############################################################################
# 3) Secrets & required vars
##############################################################################

. "$PROJECT_ROOT/config/load-secrets.sh" "Base System"
. "$PROJECT_ROOT/config/load-secrets.sh" "Obsidian Git Host"
: "${OBS_USER:?OBS_USER must be set in secrets}"
: "${GIT_USER:?GIT_USER must be set in secrets}"
: "${VAULT:?VAULT must be set in secrets}"
: "${GIT_SERVER:?GIT_SERVER must be set in secrets}"
: "${ADMIN_USER:?ADMIN_USER must be set in secrets}"

OBS_HOME="/home/${OBS_USER}"
BARE_REPO="/home/${GIT_USER}/vaults/${VAULT}.git"
WORK_TREE="${OBS_HOME}/vaults/${VAULT}"

##############################################################################
# 4) Test helpers
##############################################################################

run_test() {
  cmd="$1"
  desc="$2"
  inspect="$3"
  if [ "$DEBUG_MODE" -eq 1 ]; then

    echo "DEBUG(run_test): $desc -> $cmd" >&2
    if [ -n "$inspect" ]; then
      inspect_out="$(eval "$inspect" 2>&1 || true)"
      [ -n "$inspect_out" ] && printf '%s\n' "DEBUG(run_test): inspect ->\n$inspect_out" >&2

    fi
  fi
  output="$(eval "$cmd" 2>&1)"
  status=$?
  if [ "$DEBUG_MODE" -eq 1 ]; then
    echo "DEBUG(run_test): exit_status=$status" >&2
    [ -n "$output" ] && printf '%s\n' "DEBUG(run_test): output ->\n$output" >&2

  fi
  if [ $status -eq 0 ]; then
    echo "ok - $desc"
  else
    echo "not ok - $desc"
    [ -n "$output" ] && {
      echo "# ── Output for failed test: $desc ──"
      echo "$output" | sed 's/^/# /'
    }
    mark_test_failed
  fi
}

assert_file_perm() {
  run_test "stat -f '%Lp' \"$1\" | grep -q '^$2$'" "$3" "stat -f '%Sp' \"$1\""
}

assert_user_shell() {
  run_test "grep -q \"^$1:.*:$2\$\" /etc/passwd" "$3" "grep \"^$1:\" /etc/passwd"
}

check_entry() {
  run_test "git config --file \"$1\" --get-all safe.directory | grep -Fxq \"$2\"" \
           "safe.directory for $3: $2" \
           "git config --file \"$1\" --get-all safe.directory"
}

##############################################################################
# 5) Define & run tests
##############################################################################

  run_tests() {
    [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): starting obsidian-git-host tests" >&2
    echo "1..59"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 4 packages" >&2
  run_test "command -v git"                                              "git is installed" "command -v git"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 5 users & group" >&2

  run_test "id ${OBS_USER}"                                              "user '${OBS_USER}' exists" "id ${OBS_USER}"
  assert_user_shell "${OBS_USER}" "/bin/ksh"                              "shell for '${OBS_USER}' is /bin/ksh"
  run_test "id ${GIT_USER}"                                              "user '${GIT_USER}' exists" "id ${GIT_USER}"
  assert_user_shell "${GIT_USER}" "/usr/local/bin/git-shell"             "shell for '${GIT_USER}' is git-shell"
  run_test "getent group vault"                                          "group 'vault' exists" "getent group vault"
  run_test "id -nG ${OBS_USER} | grep -qw vault"                         "user '${OBS_USER}' is in group 'vault'" \
           "id -nG ${OBS_USER}"
  run_test "id -nG ${GIT_USER} | grep -qw vault"                         "user '${GIT_USER}' is in group 'vault'" \
           "id -nG ${GIT_USER}"

    [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 6 doas config" >&2

    run_test "[ -f /etc/doas.conf ]"                                          "doas.conf exists" \
           "ls -l /etc/doas.conf"
    run_test "grep -q \"^permit persist ${ADMIN_USER} as root\$\" /etc/doas.conf" \
            "doas.conf retains admin rule for ${ADMIN_USER}" \
            "grep '^permit persist' /etc/doas.conf"
    run_test "grep -q \"^permit persist ${OBS_USER} as root\$\" /etc/doas.conf" \
            "doas.conf allows persist ${OBS_USER}" \
            "grep '\^permit' /etc/doas.conf"
  run_test "grep -q \"^permit nopass ${GIT_USER} as root cmd git\\*\\\$\" /etc/doas.conf" \
           "doas.conf allows nopass ${GIT_USER} for git" \
           "grep '${GIT_USER}' /etc/doas.conf"
  run_test "grep -q \"^permit nopass ${GIT_USER} as ${OBS_USER} cmd git\\*\\\$\" /etc/doas.conf" \
           "doas.conf allows nopass ${GIT_USER} for working clone" \
           "grep '${GIT_USER}' /etc/doas.conf"
  assert_file_perm "/etc/doas.conf" "440"                                  "/etc/doas.conf has mode 440"
  run_test "stat -f '%Su:%Sg' /etc/doas.conf | grep -q '^root:wheel\$'"       "/etc/doas.conf owned by root:wheel" \
           "stat -f '%Su:%Sg' /etc/doas.conf"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 7.1 SSH service & config" >&2

  run_test "allow_line=\$(grep '^AllowUsers' /etc/ssh/sshd_config); echo \"\$allow_line\" | grep -qw ${ADMIN_USER} && echo \"\$allow_line\" | grep -qw ${OBS_USER} && echo \"\$allow_line\" | grep -qw ${GIT_USER}" \
           "sshd_config allows ${ADMIN_USER}, ${OBS_USER}, ${GIT_USER}" \
           "grep '^AllowUsers' /etc/ssh/sshd_config"
  run_test "pgrep -x sshd >/dev/null"                                       "sshd daemon running" \
           "pgrep -x sshd || true"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 7.2 .ssh directories" >&2

  run_test "[ -d /home/${GIT_USER}/.ssh ]"                                  "ssh dir for ${GIT_USER} exists" \
           "ls -ld /home/${GIT_USER}/.ssh"
  assert_file_perm "/home/${GIT_USER}/.ssh" "700"                            "ssh dir perms for ${GIT_USER}"
  run_test "stat -f '%Su:%Sg' /home/${GIT_USER}/.ssh | grep -q '^${GIT_USER}:${GIT_USER}\$'" \
           "ssh dir owner for ${GIT_USER}" \
           "stat -f '%Su:%Sg' /home/${GIT_USER}/.ssh"
  run_test "[ -d ${OBS_HOME}/.ssh ]"                                        "ssh dir for ${OBS_USER} exists" \
           "ls -ld ${OBS_HOME}/.ssh"
  assert_file_perm "${OBS_HOME}/.ssh" "700"                                 "ssh dir perms for ${OBS_USER}"
  run_test "stat -f '%Su:%Sg' ${OBS_HOME}/.ssh | grep -q '^${OBS_USER}:${OBS_USER}\$'" \
           "ssh dir owner for ${OBS_USER}" \
           "stat -f '%Su:%Sg' ${OBS_HOME}/.ssh"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 7.2 authorized_keys for ${GIT_USER}" >&2

  run_test "[ -f /home/${GIT_USER}/.ssh/authorized_keys ]"                           "authorized_keys for ${GIT_USER} exists" \
           "ls -l /home/${GIT_USER}/.ssh/authorized_keys"
  assert_file_perm "/home/${GIT_USER}/.ssh/authorized_keys" "600"                     "authorized_keys perms for ${GIT_USER}"
  run_test "stat -f '%Su:%Sg' /home/${GIT_USER}/.ssh/authorized_keys | grep -q '^${GIT_USER}:${GIT_USER}\$'" \
           "authorized_keys owner for ${GIT_USER}" \
           "stat -f '%Su:%Sg' /home/${GIT_USER}/.ssh/authorized_keys"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 7.2 authorized_keys for ${OBS_USER}" >&2

  run_test "[ -f ${OBS_HOME}/.ssh/authorized_keys ]"                                  "authorized_keys for ${OBS_USER} exists" \
           "ls -l ${OBS_HOME}/.ssh/authorized_keys"
  assert_file_perm "${OBS_HOME}/.ssh/authorized_keys"             "600"               "authorized_keys perms for ${OBS_USER}"
  run_test "stat -f '%Su:%Sg' ${OBS_HOME}/.ssh/authorized_keys | grep -q '^${OBS_USER}:${OBS_USER}\$'" \
           "authorized_keys owner for ${OBS_USER}" \
           "stat -f '%Su:%Sg' ${OBS_HOME}/.ssh/authorized_keys"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 7.3 known hosts for ${OBS_USER}" >&2

  run_test "[ -f ${OBS_HOME}/.ssh/known_hosts ]"                                      "known_hosts for ${OBS_USER} exists" \
           "ls -l ${OBS_HOME}/.ssh/known_hosts"
  assert_file_perm "${OBS_HOME}/.ssh/known_hosts"               "644"                  "known_hosts perms for ${OBS_USER}"
  run_test "stat -f '%Su:%Sg' ${OBS_HOME}/.ssh/known_hosts | grep -q '^${OBS_USER}:${OBS_USER}\$'" \
           "known_hosts owner for ${OBS_USER}" \
           "stat -f '%Su:%Sg' ${OBS_HOME}/.ssh/known_hosts"
  run_test "grep -q \"${GIT_SERVER}\" ${OBS_HOME}/.ssh/known_hosts"                   "known_hosts contains entry for ${GIT_SERVER}" \
           "grep \"${GIT_SERVER}\" ${OBS_HOME}/.ssh/known_hosts"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 8 repo paths & bare init" >&2
  run_test "[ -d ${BARE_REPO} ]"                                             "bare repository exists" \
           "ls -ld ${BARE_REPO}"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 9 git configs" >&2

  check_entry "/home/${GIT_USER}/.gitconfig"       "${BARE_REPO}"             "${GIT_USER}"
  check_entry "/home/${GIT_USER}/.gitconfig"       "${OBS_HOME}/vaults/${VAULT}" "${GIT_USER}"
  check_entry "${OBS_HOME}/.gitconfig"             "${OBS_HOME}/vaults/${VAULT}" "${OBS_USER}"
  run_test "grep -q '^\[core\]\$' ${BARE_REPO}/config"                       "config file contains '[core]' section" \
           "grep '^\[core\]' ${BARE_REPO}/config"
  run_test "grep -q '^[[:space:]]*sharedRepository = group\$' ${BARE_REPO}/config" \
           "config file sets 'sharedRepository = group' under [core]" \
           "grep 'sharedRepository' ${BARE_REPO}/config"


  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 10 post-receive hook" >&2

  run_test "[ -x ${BARE_REPO}/hooks/post-receive ]"                          "post-receive hook executable" \
           "ls -l ${BARE_REPO}/hooks/post-receive"
  run_test "grep -q '^#!/bin/sh\$' ${BARE_REPO}/hooks/post-receive"           "hook shebang correct" \
           "head -n 1 ${BARE_REPO}/hooks/post-receive"
  run_test "grep -q \"^SHA=\\\$(cat \\\"${BARE_REPO}/refs/heads/master\\\")\\\$\" \"${BARE_REPO}/hooks/post-receive\"" \
           "hook: SHA variable set correctly" \
           "grep '^SHA=' ${BARE_REPO}/hooks/post-receive"
  run_test "grep -q '^su - ${OBS_USER} -c \"/usr/local/bin/git --git-dir=${BARE_REPO} --work-tree=${WORK_TREE} checkout -f \\\$SHA\"\$' ${BARE_REPO}/hooks/post-receive" \
           "hook: git checkout command correct" \
           "grep 'git --git-dir' ${BARE_REPO}/hooks/post-receive"
  run_test "grep -q '^exit 0\$' ${BARE_REPO}/hooks/post-receive"             "hook: exits cleanly" \
           "tail -n 1 ${BARE_REPO}/hooks/post-receive"


  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 11 working copy clone" >&2

  run_test "[ -d ${OBS_HOME}/vaults/${VAULT}/.git ]"                          "working clone exists" \
           "ls -ld ${OBS_HOME}/vaults/${VAULT}/.git"
  run_test "su - ${OBS_USER} -c \"git -C ${OBS_HOME}/vaults/${VAULT} remote get-url origin | grep -q '${BARE_REPO}'\"" \
           "working clone origin correct" \
           "su - ${OBS_USER} -c \"git -C ${OBS_HOME}/vaults/${VAULT} remote -v\""
  run_test "su - ${OBS_USER} -c \"git -C ${OBS_HOME}/vaults/${VAULT} log -1 --pretty=%B | grep -q 'initial commit'\"" \
           "initial commit present" \
           "su - ${OBS_USER} -c \"git -C ${OBS_HOME}/vaults/${VAULT} log -1 --pretty=%B\""

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 12 final perms on bare repo" >&2

  run_test "stat -f '%Su:%Sg' ${BARE_REPO} | grep -q '^${GIT_USER}:vault\$'"   "ownership of '${BARE_REPO}' is '${GIT_USER}:vault'" \
           "stat -f '%Su:%Sg' ${BARE_REPO}"
  # Debug helpers (uncomment for troubleshooting)
  # echo "GIT_USER='${GIT_USER}', BARE_REPO='${BARE_REPO}'"
  # echo "first ownership violation, if any:"
  # find "$BARE_REPO" \( ! -user "$GIT_USER" -o ! -group vault \) -print -ls | head -n 20
  # echo "raw exit status of the find pipeline (without !):"
  # find "$BARE_REPO" \( ! -user "$GIT_USER" -o ! -group vault \) -print | grep -q .; echo "grep exit=$?"
  run_test "! find ${BARE_REPO} \( -not -user ${GIT_USER} -or -not -group vault \) -print | grep -q ." \
           "all files under '${BARE_REPO}' are owned by ${GIT_USER}:vault" \
           "find ${BARE_REPO} \( -not -user ${GIT_USER} -or -not -group vault \) -print | head -n 20"
  run_test "! find ${BARE_REPO} -not -perm -g=r -print | grep -q ."          "all entries under '${BARE_REPO}' are group-readable" \
           "find ${BARE_REPO} -not -perm -g=r -print | head -n 20"
  run_test "! find ${BARE_REPO} -not -perm -g=w -print | grep -q ."          "all entries under '${BARE_REPO}' are group-writable" \
           "find ${BARE_REPO} -not -perm -g=w -print | head -n 20"
  run_test "! find ${BARE_REPO} -type d -not -perm -g=x -print | grep -q ."  "all directories under '${BARE_REPO}' are group-executable" \
           "find ${BARE_REPO} -type d -not -perm -g=x -print | head -n 20"
  run_test "! find ${BARE_REPO} -type d -not -perm -g+s -print | grep -q ."  "all directories under '${BARE_REPO}' have the setgid bit set" \
           "find ${BARE_REPO} -type d -not -perm -g+s -print | head -n 20"

  [ "$DEBUG_MODE" -eq 1 ] && echo "DEBUG(run_tests): Section 13 history settings" >&2

  run_test "grep -q '^export HISTFILE=/home/${OBS_USER}/.ksh_history\$' /home/${OBS_USER}/.profile" \
           "HISTFILE export in ${OBS_USER} .profile" \
           "grep 'HISTFILE' /home/${OBS_USER}/.profile"
  run_test "grep -q '^export HISTSIZE=5000\$' /home/${OBS_USER}/.profile"        "HISTSIZE export in ${OBS_USER} .profile" \
           "grep 'HISTSIZE' /home/${OBS_USER}/.profile"
  run_test "grep -q '^export HISTCONTROL=ignoredups\$' /home/${OBS_USER}/.profile" \
           "HISTCONTROL export in ${OBS_USER} .profile" \
           "grep 'HISTCONTROL' /home/${OBS_USER}/.profile"
  run_test "grep -q '^export HISTFILE=/home/${GIT_USER}/.ksh_history\$' /home/${GIT_USER}/.profile" \
           "HISTFILE export in ${GIT_USER} .profile" \
           "grep 'HISTFILE' /home/${GIT_USER}/.profile"
  run_test "grep -q '^export HISTSIZE=5000\$' /home/${GIT_USER}/.profile"        "HISTSIZE export in ${GIT_USER} .profile" \
           "grep 'HISTSIZE' /home/${GIT_USER}/.profile"
  run_test "grep -q '^export HISTCONTROL=ignoredups\$' /home/${GIT_USER}/.profile" \
           "HISTCONTROL export in ${GIT_USER} .profile" \
           "grep 'HISTCONTROL' /home/${GIT_USER}/.profile"
}

run_tests

##############################################################################
# 6) Exit with status
##############################################################################

if [ "$TEST_FAILED" -ne 0 ]; then
  exit 1
else
  exit 0
fi
