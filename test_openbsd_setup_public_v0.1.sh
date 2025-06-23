#!/bin/sh
#
# test_openbsd_setup.sh - Verify OpenBSD server config for Git-synced vaults
# Author: deadhedd
# License: MIT or 0BSD (see LICENSE file)
#
# This script verifies whether an OpenBSD server has been correctly configured
# to host a Git-backed Obsidian vault, checking users, permissions, network,
# live connectivity, SSH hardening, and Git setup.

# Configuration (override via env vars)
REG_USER=${REG_USER:-obsidian}
GIT_USER=${GIT_USER:-git}
VAULT=${VAULT:-vault}
INTERFACE=${INTERFACE:-em0}
STATIC_IP=${STATIC_IP:-192.0.2.10}
NETMASK=${NETMASK:-255.255.255.0}
GATEWAY=${GATEWAY:-192.0.2.1}
DNS1=${DNS1:-1.1.1.1}
DNS2=${DNS2:-9.9.9.9}
SETUP_DIR=${SETUP_DIR:-/root/openbsd-server}

# Test Framework
tests=0
fails=0
run_test() {
  tests=`expr "$tests" + 1`
  desc="$2"
  if eval "$1" >/dev/null 2>&1; then
    echo "ok $tests - $desc"
  else
    echo "not ok $tests - $desc"
    fails=`expr "$fails" + 1`
  fi
}

# Assertion Helpers
assert_file_perm() {
  run_test "stat -f '%Lp' \"$1\" | grep -q '^$2\$'" "$3"
}
assert_user_shell() {
  run_test "grep -q \"^$1:.*:$2\$\" /etc/passwd" "$3"
}
assert_git_safe() {
  run_test "su - \"$REG_USER\" -c \"git config --global --get-all safe.directory | grep -q '^$1\$'\"" "$2"
}

#
# Begin Tests
#

# 1-5: Users & shells
assert_user_shell "$REG_USER" "/bin/ksh" "user '$REG_USER' exists with ksh shell"
assert_user_shell "$GIT_USER" "/usr/local/bin/git-shell" "user '$GIT_USER' exists with git-shell"

# 6: doas permissions
assert_file_perm /etc/doas.conf 440 "/etc/doas.conf not world-readable"

# 7-10: Static network config
run_test "grep -q \"inet ${STATIC_IP}.*netmask ${NETMASK}\" \"/etc/hostname.${INTERFACE}\"" "IP/netmask set on ${INTERFACE}"
run_test "grep -q \"!route add default ${GATEWAY}\" \"/etc/hostname.${INTERFACE}\"" "gateway ${GATEWAY} set on ${INTERFACE}"
run_test "grep -q \"nameserver ${DNS1}\" /etc/resolv.conf" "DNS1 ${DNS1} in resolv.conf"
run_test "grep -q \"nameserver ${DNS2}\" /etc/resolv.conf" "DNS2 ${DNS2} in resolv.conf"

# 11-13: Live network & DNS
run_test "ifconfig \"${INTERFACE}\" | grep -q 'status: active'" "${INTERFACE} is up"
run_test "ping -c3 ${GATEWAY} >/dev/null" "gateway ${GATEWAY} reachable"
run_test "host github.com >/dev/null 2>&1" "DNS can resolve github.com"

# 14-16: SSH hardening
run_test "grep -q \"^AllowUsers\" /etc/ssh/sshd_config \
  && grep -q \"\<${REG_USER}\>\" /etc/ssh/sshd_config \
  && grep -q \"\<${GIT_USER}\>\" /etc/ssh/sshd_config" "sshd_config allows only ${REG_USER},${GIT_USER}"
run_test "sshd -T | grep -q '^permitrootlogin no\$'" "PermitRootLogin disabled"
run_test "sshd -T | grep -q '^passwordauthentication no\$'" "PasswordAuthentication disabled"

# 17: Git installed
run_test "command -v git" "git is on \$PATH"

# 18-21: Vault repos & safety
run_test "[ -d \"/home/${GIT_USER}/vaults/${VAULT}.git\" ]" "bare repo exists"
run_test "[ \"\`stat -f '%Su' \"/home/${GIT_USER}/vaults/${VAULT}.git\"\`\" = \"${GIT_USER}\" ]" "bare repo owned by ${GIT_USER}"
run_test "[ -x \"/home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive\" ]" "post-receive hook executable"
run_test "[ -d \"/home/${REG_USER}/vaults/${VAULT}/.git\" ]" "working clone exists"
assert_git_safe "/home/${REG_USER}/vaults/${VAULT}" "working clone marked safe.directory"

# 22: Vault push dry-run
run_test "su - \"$REG_USER\" -c \"git -C \\\"/home/${REG_USER}/vaults/${VAULT}\\\" push --dry-run origin HEAD:refs/heads/tap-test\"" \
  "obsidian user can push to vault repo (dry-run)"

# 23-25: Setup-script GitHub repo & push
run_test "[ -d \"${SETUP_DIR}/.git\" ]" "setup-script directory is a Git repo"
run_test "git -C \"${SETUP_DIR}\" remote get-url origin >/dev/null 2>&1" "origin set on setup-script"
run_test "git -C \"${SETUP_DIR}\" push --dry-run >/dev/null 2>&1" "dry-run push works from setup-script"
run_test "ssh -T git@github.com 2>&1 | grep -q 'successfully authenticated'" \
  "SSH key can authenticate to GitHub"

# 26-27: Profile history
run_test "grep -q HISTFILE /home/${REG_USER}/.profile" "${REG_USER} .profile sets HISTFILE"
run_test "grep -q HISTFILE /home/${GIT_USER}/.profile" "${GIT_USER} .profile sets HISTFILE"

#
# Final TAP plan & summary
#
echo "1..$tests"
echo ""
if [ "$fails" -eq 0 ]; then
  echo "All $tests tests passed."
else
  echo "$fails of $tests tests failed."
fi

exit "$fails"
