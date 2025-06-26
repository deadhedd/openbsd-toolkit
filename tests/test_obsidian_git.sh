#!/bin/sh
#
# test_obsidian_sync.sh - Verify git-backed Obsidian sync configuration
# Usage: ./test_obsidian_sync.sh

#–––– Configuration ––––
REG_USER=${REG_USER:-obsidian}
GIT_USER=${GIT_USER:-git}
VAULT=${VAULT:-vault}

#–––– Test Framework ––––
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
  run_test "su - $REG_USER -c \"git config --global --get-all safe.directory | grep -q '^$repo\$'\"" "$desc"
}

#–––– Begin Test Plan ––––
echo "1..7"

# 1: bare repo exists
run_test "[ -d /home/${GIT_USER}/vaults/${VAULT}.git ]" "bare repo exists"
# 2: bare repo ownership
run_test "stat -f '%Su' /home/${GIT_USER}/vaults/${VAULT}.git | grep -q '^${GIT_USER}\$'" "bare repo is owned by '${GIT_USER}'"
# 3: post-receive hook executable
run_test "[ -x /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive ]" "post-receive hook is executable"
# 4: post-receive hook ownership
run_test "stat -f '%Su:%Sg' /home/${GIT_USER}/vaults/${VAULT}.git/hooks/post-receive | grep -q '^${GIT_USER}:${GIT_USER}\$'" "post-receive hook owned by ${GIT_USER}"
# 5: bare repo HEAD
run_test "[ -f /home/${GIT_USER}/vaults/${VAULT}.git/HEAD ]" "bare repo HEAD exists"
# 6: working clone for REG_USER
run_test "[ -d /home/${REG_USER}/vaults/${VAULT}/.git ]" "working clone exists for '${REG_USER}'"
# 7: safe.directory set
assert_git_safe "/home/${REG_USER}/vaults/${VAULT}" "safe.directory configured for working clone"

#–––– Summary ––––
echo ""
[ "$fails" -eq 0 ] && echo "✅ All $tests tests passed." || echo "❌ $fails of $tests tests failed."
exit $fails
