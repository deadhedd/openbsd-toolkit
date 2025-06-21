#!/bin/sh
#
# test_openbsd_setup.sh - Verify OpenBSD server config for Git-synced vaults
# Author: deadhedd
# License: MIT or 0BSD (see LICENSE file)
#
# This script verifies whether an OpenBSD server has been correctly configured
# to host a Git-backed Obsidian vault, checking users, permissions, network,
# and Git setup.

# Configuration (override via env vars)
REG_USER=${REG_USER:-obsidian}
GIT_USER=${GIT_USER:-git}
VAULT=${VAULT:-vault}
INTERFACE=${INTERFACE:-em0}
STATIC_IP=${STATIC_IP:-192.0.2.10}      # Reserved for documentation/examples
NETMASK=${NETMASK:-255.255.255.0}
GATEWAY=${GATEWAY:-192.0.2.1}
DNS1=${DNS1:-1.1.1.1}
DNS2=${DNS2:-8.8.8.8}

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
  path=$1; want_mode=$2; desc=$3
  run_test "stat -f '%Lp' $path | grep -q '^$want_mode\$'" "$desc"
}

assert_user_shell() {
  user=$1; shell=$2; desc=$3
  run_test "grep -q \"^$user:.*:$shell\$\" /etc/passwd" "$desc"
}

assert_git_safe() {
  repo=$1; desc=$2
  run_test "su - $REG_USER -c \"git config --global --get-all safe.directory | grep -q '^$repo\$'\"" "$desc"
}

# Begin Test Plan 
echo "1..19"

# User and Shell Checks
run_test "id $REG_USER" "user '$REG_USER' exists"
assert_user_shell "$REG_USER" "/bin/ksh" "shell for '$REG_USER' is /bin/ksh"

run_test "id $GIT_USER" "user '$GIT_USER' exists"
assert_user_shell "$GIT_USER" "/usr/local/bin/git-shell" "shell for '$GIT_USER' is git-shell"

# doas.conf Permissions
assert_file_perm "/etc/doas.conf" "0440" "/etc/doas.conf has correct permissions"

# Network Configuration
run_test "grep -q \"inet $STATIC_IP.*netmask $NETMASK\" /etc/hostname.$INTERFACE" "hostname.$INTERFACE has IP/netmask"
run_test "grep -q \"!route add default $GATEWAY\" /etc/hostname.$INTERFACE" "hostname.$INTERFACE has gateway"

# DNS
run_test "grep -q \"nameserver $DNS1\" /etc/resolv.conf" "resolv.conf contains DNS1"
run_test "grep -q \"nameserver $DNS2\" /etc/resolv.conf" "resolv.conf contains DNS2"

# SSHD Configuration
run_test "grep -q \"^AllowUsers.*$REG_USER.*$GIT_USER\" /etc/ssh/sshd_config" "sshd_config has AllowUsers"
run_test "grep -q \"^PermitRootLogin no\" /etc/ssh/sshd_config" "sshd_config disallows root login"

# Git Installed
run_test "command -v git" "git is installed"

# Git Repo Checks
run_test "[ -d /home/$GIT_USER/vaults/$VAULT.git ]" "bare repo exists"
run_test "[ \"\`stat -f '%Su' /home/$GIT_USER/vaults/$VAULT.git\`\" = \"$GIT_USER\" ]" "bare repo is owned by '$GIT_USER'"
run_test "[ -x /home/$GIT_USER/vaults/$VAULT.git/hooks/post-receive ]" "post-receive hook is executable"
run_test "[ -d /home/$REG_USER/vaults/$VAULT/.git ]" "working clone exists for '$REG_USER'"
assert_git_safe "/home/$REG_USER/vaults/$VAULT" "safe.directory configured for working clone"

# Profile Config Checks
run_test "grep -q HISTFILE /home/$REG_USER/.profile" "$REG_USER .profile sets history"
run_test "grep -q HISTFILE /home/$GIT_USER/.profile" "$GIT_USER .profile sets history"

# Summary
echo ""
if [ "$fails" -eq 0 ]; then
  echo "✅ All $tests tests passed."
else
  echo "❌ $fails of $tests tests failed."
fi

exit "$fails"
