#!/bin/sh
#
# modules/obsidian-git-host/test.sh — Verify Obsidian vault sync configuration
# Author: deadhedd
# Version: 1.0.0
# Updated: 2025-07-28
#
# Usage: ./test.sh [--log[=FILE]] [--debug] [-h]
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
#   Enabling the --debug flag will log all executed commands *and their expanded
#   values* (via `set -vx`), including any exported secrets or credentials.
#   Use caution when sharing or retaining debug logs.
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
  cat <<-EOF
  Usage: $(basename "$0") [options]

  Description:
    Validate Obsidian vault sync setup on the Git host

  Options:
    -h, --help        Show this help message and exit
    -d, --debug       Enable debug mode
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

. "$PROJECT_ROOT/config/load_secrets.sh"
: "${OBS_USER:?OBS_USER must be set in secrets}"
: "${GIT_USER:?GIT_USER must be set in secrets}"
: "${VAULT:?VAULT must be set in secrets}"
: "${GIT_SERVER:?GIT_SERVER must be set in secrets}"

OBS_HOME="/home/${OBS_USER}"
BARE_REPO="/home/${GIT_USER}/vaults/${VAULT}.git"
WORK_TREE="${OBS_HOME}/vaults/${VAULT}"

##############################################################################
# 4) Test helpers
##############################################################################

run_test() {
  desc="$2"
  if eval "$1" >/dev/null 2>&1; then
    echo "ok - $desc"
  else
    echo "not ok - $desc"
    mark_test_failed
  fi
}

assert_file_perm() {
  run_test "stat -f '%Lp' \"$1\" | grep -q '^$2\$'" "$3"
}

assert_user_shell() {
  run_test "grep -q \"^$1:.*:$2\$\" /etc/passwd" "$3"
}

check_entry() {
  run_test "git config --file \"$1\" --get-all safe.directory | grep -Fxq \"$2\"" \
           "safe.directory for $3: $2"
}

##############################################################################
# 5) Define & run tests
##############################################################################

run_tests() {
  echo "1..58"

  ### Section 4) Packages (1)
  run_test "command -v git"                                              "git is installed"

  ### Section 5) Users & group (7)
  run_test "id ${OBS_USER}"                                              "user '${OBS_USER}' exists"
  assert_user_shell "${OBS_USER}" "/bin/ksh"                              "shell for '${OBS_USER}' is /bin/ksh"
  run_test "id ${GIT_USER}"                                              "user '${GIT_USER}' exists"
  assert_user_shell "${GIT_USER}" "/usr/local/bin/git-shell"             "shell for '${GIT_USER}' is git-shell"
  run_test "getent group vault"                                          "group 'vault' exists"
  run_test "id -nG ${OBS_USER} | grep -qw vault"                         "user '${OBS_USER}' is in group 'vault'"
  run_test "id -nG ${GIT_USER} | grep -qw vault"                         "user '${GIT_USER}' is in group 'vault'"

  ### Section 6) doas config (6)
  run_test "[ -f /etc/doas.conf ]"                                          "doas.conf exists"
  run_test "grep -q \"^permit persist ${OBS_USER} as root\$\" /etc/doas.conf" \
           "doas.conf allows persist ${OBS_USER}"
  run_test "grep -q \"^permit nopass ${GIT_USER} as root cmd git\\*\\\$\" /etc/doas.conf" \
           "doas.conf allows nopass ${GIT_USER} for git"
  run_test "grep -q \"^permit nopass ${GIT_USER} as ${OBS_USER} cmd git\\*\\\$\" /etc/doas.conf" \
           "doas.conf allows nopass ${GIT_USER} for working clone"
  assert_file_perm "/etc/doas.conf" "440"                                  "/etc/doas.conf has mode 440"
  run_test "stat -f '%Su:%Sg' /etc/doas.conf | grep -q '^root:wheel\$'"       "/etc/doas.conf owned by root:wheel"

  ### Section 7) SSH hardening & per-user SSH dirs

  # 7.1 SSH Service & Config (2)
  run_test "grep -q \"^AllowUsers ${OBS_USER} ${GIT_USER}\$\" /etc/ssh/sshd_config" \
           "sshd_config has AllowUsers"
  run_test "pgrep -x sshd >/dev/null"                                       "sshd daemon running"
  
  # 7.2 .ssh Directories and authorized users (6)
  run_test "[ -d /home/${GIT_USER}/.ssh ]"                                  "ssh dir for ${GIT_USER} exists"
  assert_file_perm "/home/${GIT_USER}/.ssh" "700"                            "ssh dir perms for ${GIT_USER}"
  run_test "stat -f '%Su:%Sg' /home/${GIT_USER}/.ssh | grep -q '^${GIT_USER}:${GIT_USER}\$'" \
           "ssh dir owner for ${GIT_USER}"
  run_test "[ -d ${OBS_HOME}/.ssh ]"                                        "ssh dir for ${OBS_USER} exists"
  assert_file_perm "${OBS_HOME}/.ssh" "700"                                 "ssh dir perms for ${OBS_USER}"
  run_test "stat -f '%Su:%Sg' ${OBS_HOME}/.ssh | grep -q '^${OBS_USER}:${OBS_USER}\$'" \
           "ssh dir owner for ${OBS_USER}"

  # authorized_keys for GIT_USER (3)
  run_test "[ -f /home/${GIT_USER}/.ssh/authorized_keys ]"                           "authorized_keys for ${GIT_USER} exists"
  assert_file_perm "/home/${GIT_USER}/.ssh/authorized_keys" "600"                     "authorized_keys perms for ${GIT_USER}"
  run_test "stat -f '%Su:%Sg' /home/${GIT_USER}/.ssh/authorized_keys | grep -q '^${GIT_USER}:${GIT_USER}\$'" \
           "authorized_keys owner for ${GIT_USER}"

  # authorized_keys for OBS_USER (3)
  run_test "[ -f ${OBS_HOME}/.ssh/authorized_keys ]"                                  "authorized_keys for ${OBS_USER} exists"
  assert_file_perm "${OBS_HOME}/.ssh/authorized_keys"             "600"               "authorized_keys perms for ${OBS_USER}"
  run_test "stat -f '%Su:%Sg' ${OBS_HOME}/.ssh/authorized_keys | grep -q '^${OBS_USER}:${OBS_USER}\$'" \
           "authorized_keys owner for ${OBS_USER}"

  # 7.3 Known Hosts (OBS_USER only) (4)
  run_test "[ -f ${OBS_HOME}/.ssh/known_hosts ]"                                      "known_hosts for ${OBS_USER} exists"
  assert_file_perm "${OBS_HOME}/.ssh/known_hosts"               "644"                  "known_hosts perms for ${OBS_USER}"
  run_test "stat -f '%Su:%Sg' ${OBS_HOME}/.ssh/known_hosts | grep -q '^${OBS_USER}:${OBS_USER}\$'" \
           "known_hosts owner for ${OBS_USER}"
  run_test "grep -q \"${GIT_SERVER}\" ${OBS_HOME}/.ssh/known_hosts"                   "known_hosts contains entry for ${GIT_SERVER}"

  ### Section 8) Repo paths & bare init (1)
  run_test "[ -d ${BARE_REPO} ]"                                             "bare repository exists"

  ### Section 9) Git configs (safe.directory & sharedRepository) (5)
  check_entry "/home/${GIT_USER}/.gitconfig"       "${BARE_REPO}"             "${GIT_USER}"
  check_entry "/home/${GIT_USER}/.gitconfig"       "${OBS_HOME}/vaults/${VAULT}" "${GIT_USER}"
  check_entry "${OBS_HOME}/.gitconfig"             "${OBS_HOME}/vaults/${VAULT}" "${OBS_USER}"
  run_test "grep -q '^\[core\]\$' ${BARE_REPO}/config"                       "config file contains '[core]' section"
  run_test "grep -q '^[[:space:]]*sharedRepository = group\$' ${BARE_REPO}/config" \
           "config file sets 'sharedRepository = group' under [core]"

  ### Section 10) Post-receive hook (5)
  run_test "[ -x ${BARE_REPO}/hooks/post-receive ]"                          "post-receive hook executable"
  run_test "grep -q '^#!/bin/sh\$' ${BARE_REPO}/hooks/post-receive"           "hook shebang correct"
  run_test "grep -q \"^SHA=\\\$(cat \\\"${BARE_REPO}/refs/heads/master\\\")\\\$\" \"${BARE_REPO}/hooks/post-receive\"" \
           "hook: SHA variable set correctly"
  run_test "grep -q '^su - ${OBS_USER} -c \"/usr/local/bin/git --git-dir=${BARE_REPO} --work-tree=${WORK_TREE} checkout -f \\\$SHA\"\$' ${BARE_REPO}/hooks/post-receive" \
           "hook: git checkout command correct"
  run_test "grep -q '^exit 0\$' ${BARE_REPO}/hooks/post-receive"             "hook: exits cleanly"

  ### Section 11) Working copy clone & initial commit (3)
  run_test "[ -d ${OBS_HOME}/vaults/${VAULT}/.git ]"                          "working clone exists"
  run_test "su - ${OBS_USER} -c \"git -C ${OBS_HOME}/vaults/${VAULT} remote get-url origin | grep -q '${BARE_REPO}'\"" \
           "working clone origin correct"
  run_test "su - ${OBS_USER} -c \"git -C ${OBS_HOME}/vaults/${VAULT} log -1 --pretty=%B | grep -q 'initial commit'\"" \
           "initial commit present"

  ### Section 12) Final perms on bare repo (6)
  run_test "stat -f '%Su:%Sg' ${BARE_REPO} | grep -q '^${GIT_USER}:vault\$'"   "ownership of '${BARE_REPO}' is '${GIT_USER}:vault'"
echo "DEBUG: GIT_USER='${GIT_USER}', BARE_REPO='${BARE_REPO}'"
echo "first ownership violation, if any:"
find "$BARE_REPO" \( ! -user "$GIT_USER" -o ! -group vault \) -print -ls | head -n 20
echo "raw exit status of the find pipeline (nithout !):"
find "$BARE_REPO" \( ! -user "$GIT_USER" -o ! -group vault \) -print | grep -q .; echo "grep exit=$?"
  run_test "! find ${BARE_REPO} \( -not -user ${GIT_USER} -or -not -group vault \) -print | grep -q ." \
           "all files under '${BARE_REPO}' are owned by ${GIT_USER}:vault"
  run_test "! find ${BARE_REPO} -not -perm -g=r -print | grep -q ."          "all entries under '${BARE_REPO}' are group-readable"
  run_test "! find ${BARE_REPO} -not -perm -g=w -print | grep -q ."          "all entries under '${BARE_REPO}' are group-writable"
  run_test "! find ${BARE_REPO} -type d -not -perm -g=x -print | grep -q ."  "all directories under '${BARE_REPO}' are group-executable"
  run_test "! find ${BARE_REPO} -type d -not -perm -g+s -print | grep -q ."  "all directories under '${BARE_REPO}' have the setgid bit set"

  ### Section 13) History settings (.profile) (6)
  run_test "grep -q '^export HISTFILE=/home/${OBS_USER}/.ksh_history\$' /home/${OBS_USER}/.profile" \
           "HISTFILE export in ${OBS_USER} .profile"
  run_test "grep -q '^export HISTSIZE=5000\$' /home/${OBS_USER}/.profile"        "HISTSIZE export in ${OBS_USER} .profile"
  run_test "grep -q '^export HISTCONTROL=ignoredups\$' /home/${OBS_USER}/.profile" \
           "HISTCONTROL export in ${OBS_USER} .profile"
  run_test "grep -q '^export HISTFILE=/home/${GIT_USER}/.ksh_history\$' /home/${GIT_USER}/.profile" \
           "HISTFILE export in ${GIT_USER} .profile"
  run_test "grep -q '^export HISTSIZE=5000\$' /home/${GIT_USER}/.profile"        "HISTSIZE export in ${GIT_USER} .profile"
  run_test "grep -q '^export HISTCONTROL=ignoredups\$' /home/${GIT_USER}/.profile" \
           "HISTCONTROL export in ${GIT_USER} .profile"
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
