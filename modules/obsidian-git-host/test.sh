#!/bin/sh
#
# test.sh — Validate Obsidian vault sync configuration (obsidian-git-host module)

set -x

#
# 1) Locate project root
#
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

#
# 2) Load secrets
#
. "$PROJECT_ROOT/config/load_secrets.sh"
: "${OBS_USER:?OBS_USER must be set in secrets}"
: "${GIT_USER:?GIT_USER must be set in secrets}"
: "${VAULT:?VAULT must be set in secrets}"
: "${GIT_SERVER:?GIT_SERVER must be set in secrets}"

OBS_HOME="/home/${OBS_USER}"
BARE_REPO="/home/${GIT_USER}/vaults/${VAULT}.git"
WORK_TREE="${OBS_HOME}/vaults/${VAULT}"

#
# 3) Test helpers
#
run_test() {
  desc="$2"
  if eval "$1" >/dev/null 2>&1; then
    echo "ok - $desc"
  else
    echo "not ok - $desc"
    exit 1
  fi
}

assert_file_perm() {
  path="$1"; want="$2"; desc="$3"
  run_test "stat -f '%Lp' \"$path\" | grep -q '^$want\$'" "$desc"
}

assert_user_shell() {
  user="$1"; shell="$2"; desc="$3"
  run_test "grep -q \"^$user:.*:$shell\$\" /etc/passwd" "$desc"
}

check_entry() {
  config_file="$1"
  dir="$2"
  label="$3"
  run_test "git config --file \"$config_file\" --get-all safe.directory | grep -Fxq \"$dir\"" \
           "safe.directory for $label: $dir"
}

#
# 4) Tests
#
# Git installation
run_test "command -v git" "git is installed"

# Users & shells
run_test "id ${OBS_USER}" "user '${OBS_USER}' exists"
assert_user_shell "${OBS_USER}" "/bin/ksh" "shell for '${OBS_USER}' is /bin/ksh"
run_test "id ${GIT_USER}" "user '${GIT_USER}' exists"
assert_user_shell "${GIT_USER}" "/usr/local/bin/git-shell" "shell for '${GIT_USER}' is git-shell"

# Group 'vault' exists
run_test "getent group vault" "group 'vault' exists"

# Both users are in 'vault'
run_test "id -nG ${OBS_USER} | grep -qw vault" "user '${OBS_USER}' is in group 'vault'"
run_test "id -nG ${GIT_USER} | grep -qw vault" "user '${GIT_USER}' is in group 'vault'"

# Bare repo ownership
run_test "stat -f '%Su:%Sg' ${BARE_REPO} | grep -q '^${GIT_USER}:vault\$'" \
         "ownership of '${BARE_REPO}' is '${GIT_USER}:vault'"

# No wrong owner/group under the repo
run_test "! find ${BARE_REPO} \\( -not -user ${GIT_USER} -or -not -group vault \\) -print | grep -q ." \
         "all files under '${BARE_REPO}' are owned by ${GIT_USER}:vault"

# Permissions under bare repo
run_test "! find ${BARE_REPO} -not -perm -g=r -print | grep -q ." \
         "all entries under '${BARE_REPO}' are group-readable"
run_test "! find ${BARE_REPO} -not -perm -g=w -print | grep -q ." \
         "all entries under '${BARE_REPO}' are group-writable"
run_test "! find ${BARE_REPO} -type d -not -perm -g=x -print | grep -q ." \
         "all directories under '${BARE_REPO}' are group-executable"
run_test "! find ${BARE_REPO} -type d -not -perm -g+s -print | grep -q ." \
         "all directories under '${BARE_REPO}' have the setgid bit set"

# doas configuration
run_test "[ -f /etc/doas.conf ]" "doas.conf exists"
run_test "grep -q \"^permit persist ${OBS_USER} as root\$\" /etc/doas.conf" \
         "doas.conf allows persist ${OBS_USER}"
run_test "grep -q \"^permit nopass ${GIT_USER} as root cmd git\\*\\\$\" /etc/doas.conf" \
         "doas.conf allows nopass ${GIT_USER} for git"
run_test "grep -q \"^permit nopass ${GIT_USER} as ${OBS_USER} cmd git\\*\\\$\" /etc/doas.conf" \
         "doas.conf allows nopass ${GIT_USER} for working clone"
run_test "stat -f '%Lp' /etc/doas.conf | grep -q '^440\$'" \
         "/etc/doas.conf has mode 440"
run_test "stat -f '%Su:%Sg' /etc/doas.conf | grep -q '^root:wheel\$'" \
         "/etc/doas.conf owned by root:wheel"

# SSH hardening
run_test "grep -q \"^AllowUsers ${OBS_USER} ${GIT_USER}\$\" /etc/ssh/sshd_config" \
         "sshd_config has AllowUsers"
run_test "pgrep -x sshd >/dev/null" "sshd daemon running"

# SSH dirs for GIT_USER
run_test "[ -d /home/${GIT_USER}/.ssh ]" "ssh dir for ${GIT_USER} exists"
assert_file_perm "/home/${GIT_USER}/.ssh" "700" "ssh dir perms for ${GIT_USER}"
run_test "stat -f '%Su:%Sg' /home/${GIT_USER}/.ssh | grep -q '^${GIT_USER}:${GIT_USER}\$'" \
         "ssh dir owner for ${GIT_USER}"

# SSH dirs for OBS_USER
run_test "[ -d ${OBS_HOME}/.ssh ]" "ssh dir for ${OBS_USER} exists"
assert_file_perm "${OBS_HOME}/.ssh" "700" "ssh dir perms for ${OBS_USER}"
run_test "stat -f '%Su:%Sg' ${OBS_HOME}/.ssh | grep -q '^${OBS_USER}:${OBS_USER}\$'" \
         "ssh dir owner for ${OBS_USER}"

# known_hosts for OBS_USER
run_test "[ -f ${OBS_HOME}/.ssh/known_hosts ]" "known_hosts for ${OBS_USER} exists"
run_test "grep -q \"^${GIT_SERVER}\" ${OBS_HOME}/.ssh/known_hosts" \
         "known_hosts contains ${GIT_SERVER}"
assert_file_perm "${OBS_HOME}/.ssh/known_hosts" "644" "known_hosts perms for ${OBS_USER}"
run_test "stat -f '%Su:%Sg' ${OBS_HOME}/.ssh/known_hosts | grep -q '^${OBS_USER}:${OBS_USER}\$'" \
         "known_hosts owner correct"

# safe.directory entries
check_entry "/home/${GIT_USER}/.gitconfig" "${BARE_REPO}"          "${GIT_USER}"
check_entry "/home/${GIT_USER}/.gitconfig" "${OBS_HOME}/vaults/${VAULT}" "${GIT_USER}"
check_entry "${OBS_HOME}/.gitconfig"       "${OBS_HOME}/vaults/${VAULT}" "${OBS_USER}"

# post-receive hook
run_test "[ -x ${BARE_REPO}/hooks/post-receive ]" "post-receive hook executable"
run_test "grep -q '^#!/bin/sh\$' ${BARE_REPO}/hooks/post-receive"      "hook shebang correct"
run_test "grep -q '^SHA=\\\$\\(cat ${BARE_REPO}/refs/heads/master\\)\$' ${BARE_REPO}/hooks/post-receive" \
         "hook: SHA variable set correctly"
run_test "grep -q '^su - ${OBS_USER} -c \"/usr/local/bin/git --git-dir=${BARE_REPO} --work-tree=${WORK_TREE} checkout -f \\$SHA\"\$' ${BARE_REPO}/hooks/post-receive" \
         "hook: git checkout command correct"
run_test "grep -q '^exit 0\$' ${BARE_REPO}/hooks/post-receive"        "hook: exits cleanly"

# Git config core.sharedRepository
run_test "grep -q '^\[core\]\$' ${BARE_REPO}/config"                  "config file contains '[core]' section"
run_test "grep -q '^[[:space:]]*sharedRepository = group\$' ${BARE_REPO}/config" \
         "config file sets 'sharedRepository = group' under [core]"

# Working clone & initial commit
run_test "[ -d ${OBS_HOME}/vaults/${VAULT}/.git ]"                     "working clone exists"
run_test "su - ${OBS_USER} -c \"git -C ${OBS_HOME}/vaults/${VAULT} remote get-url origin | grep -q '${BARE_REPO}'\"" \
         "working clone origin correct"
run_test "su - ${OBS_USER} -c \"git -C ${OBS_HOME}/vaults/${VAULT} log -1 --pretty=%B | grep -q 'initial commit'\"" \
         "initial commit present"

echo "✅ obsidian-git-host tests passed."

