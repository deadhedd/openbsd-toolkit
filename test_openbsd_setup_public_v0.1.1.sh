#!/bin/sh
#
# test_openbsd_setup.sh - Verify Obsidian-Git-Host setup post-provisioning
# Usage: ./test_openbsd_setup.sh

#–––– Configuration ––––
REG_USER=${REG_USER:-obsidian}
GIT_USER=${GIT_USER:-git}
VAULT=${VAULT:-vault}            # ← align with setup.sh!
INTERFACE=${INTERFACE:-em0}
STATIC_IP=${STATIC_IP:-192.0.2.101}
NETMASK=${NETMASK:-255.255.255.0}
GATEWAY=${GATEWAY:-192.0.2.1}
DNS1=${DNS1:-1.1.1.1}
DNS2=${DNS2:-9.9.9.9}

#–––– Test Framework ––––
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

assert_file_perm() {
  path=$1; want=$2; desc=$3
  run_test "stat -f '%Lp' $path | grep -q '^$want\$'" "$desc"
}

assert_user_shell() {
  user=$1; shell=$2; desc=$3
  run_test "grep -q \"^$user:.*:$shell\$\" /etc/passwd" "$desc"
}

assert_git_safe() {
  repo=$1; desc=$2
  run_test "su - $REG_USER -c \"git config --global --get-all safe.directory | grep -q '^$repo\$'\"" "$desc"
}

#–––– Begin Test Plan ––––
echo "1..38"

#–– 1–4: User & Shell ––
run_test "id $REG_USER" "user '$REG_USER' exists"
assert_user_shell "$REG_USER" "/bin/ksh" "shell for '$REG_USER' is /bin/ksh"

run_test "id $GIT_USER" "user '$GIT_USER' exists"
assert_user_shell "$GIT_USER" "/usr/local/bin/git-shell" "shell for '$GIT_USER' is git-shell"

#–– 5–6: Package Installation ––
run_test "command -v git >/dev/null 2>&1" "git is installed"
run_test "command -v doas >/dev/null 2>&1" "doas is installed"

#–– 7–10: doas.conf perms, ownership & rules ––
assert_file_perm "/etc/doas.conf" "440" "/etc/doas.conf has correct permissions"
run_test "stat -f '%Su:%Sg' /etc/doas.conf | grep -q '^root:wheel\$'" "doas.conf owned by root:wheel"
run_test "grep -q \"^permit persist ${REG_USER} as root\$\" /etc/doas.conf" "doas.conf allows persist ${REG_USER}"
run_test "grep -q \"^permit nopass ${GIT_USER} as root cmd git\\*\" /etc/doas.conf" "doas.conf allows nopass ${GIT_USER} for git commands"

#–– 11–13: Network interface & config file ––
run_test "[ -f /etc/hostname.${INTERFACE} ]" "interface config file exists"
run_test "grep -q \"inet ${STATIC_IP}.*netmask ${NETMASK}\" /etc/hostname.${INTERFACE}" "hostname.${INTERFACE} has IP/netmask"
run_test "grep -q \"!route add default ${GATEWAY}\" /etc/hostname.${INTERFACE}" "hostname.${INTERFACE} has gateway"

#–– 14: Default route in kernel table ––
run_test "netstat -rn | grep -q '^default[[:space:]]*${GATEWAY}'" "default route via ${GATEWAY} present"

#–– 15–18: DNS & resolv.conf ––
run_test "[ -f /etc/resolv.conf ]" "resolv.conf exists"
run_test "grep -q \"nameserver ${DNS1}\" /etc/resolv.conf" "resolv.conf contains DNS1"
run_test "grep -q \"nameserver ${DNS2}\" /etc/resolv.conf" "resolv.conf contains DNS2"
assert_file_perm "/etc/resolv.conf" "644" "resolv.conf mode is 644"

#–– 19–21: SSH daemon & config ––
run_test "rcctl check sshd >/dev/null 2>&1" "sshd service is running"
run_test "grep -q \"^AllowUsers.*${REG_USER}.*${GIT_USER}\" /etc/ssh/sshd_config" "sshd_config has AllowUsers"
run_test "grep -q \"^PermitRootLogin no\" /etc/ssh/sshd_config" "sshd_config disallows root login"

#–– 22–28: Git vault setup ––
run_test "[ -d /home/${GIT_USER}/vaults/${VAULT}.git ]" "bare repo exists"
run_test "stat -f '%Su' /home/${GIT_USER}/vaults/${VAULT}.git | grep -q '^${GIT_USER}\$'" "bare repo is owned by '${GIT_USER}'"
run_test "[ -x /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive ]" "post-receive hook is executable"
run_test "stat -f '%Su:%Sg' /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive | grep -q '^${GIT_USER}:${GIT_USER}\$'" "post-receive hook owned by ${GIT_USER}"
run_test "[ -f /home/${GIT_USER}/vaults/${VAULT}.git/HEAD ]" "bare repo HEAD exists"
run_test "[ -d /home/${REG_USER}/vaults/${VAULT}/.git ]" "working clone exists for '${REG_USER}'"
assert_git_safe "/home/${REG_USER}/vaults/${VAULT}" "safe.directory configured for working clone"

#–– 29–30: Shell history config ––
run_test "grep -q '^export HISTFILE=\\\$HOME/.histfile' /home/${REG_USER}/.profile" "${REG_USER} .profile sets HISTFILE"
run_test "grep -q '^export HISTFILE=\\\$HOME/.histfile' /home/${GIT_USER}/.profile" "${GIT_USER} .profile sets HISTFILE"

#–– 31–34: Home directory existence & ownership ––
run_test "[ -d \"/home/${REG_USER}\" ]" "home directory for ${REG_USER} exists"
run_test "stat -f '%Su' /home/${REG_USER} | grep -q '^${REG_USER}\$'" "${REG_USER} owns their home"
run_test "[ -d \"/home/${GIT_USER}\" ]" "home directory for ${GIT_USER} exists"
run_test "stat -f '%Su' /home/${GIT_USER} | grep -q '^${GIT_USER}\$'" "${GIT_USER} owns their home"

#–– 35–38: SSH deploy key & known_hosts ––
run_test "[ -f /root/.ssh/id_ed25519 ]" "deploy key present"
assert_file_perm "/root/.ssh/id_ed25519" "600" "deploy key mode is 600"
run_test "[ -f /root/.ssh/known_hosts ]" "root known_hosts exists"
run_test "grep -q '^github\\.com ' /root/.ssh/known_hosts" "known_hosts contains github.com"

#–––– Summary ––––
echo ""
if [ "`expr \"$fails\" + 0`" -eq 0 ]; then
  echo "✅ All $tests tests passed."
else
  echo "❌ $fails of $tests tests failed."
fi

exit "$fails"
