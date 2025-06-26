#!/bin/sh
#
# test_github_config.sh - Verify GitHub SSH key & known_hosts for deploy
# Usage: ./test_github_config.sh

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

#–––– Begin Test Plan ––––
echo "1..4"

# 1: deploy key present
run_test "[ -f /root/.ssh/id_ed25519 ]" "deploy key present"
# 2: deploy key permissions
assert_file_perm "/root/.ssh/id_ed25519" "600" "deploy key mode is 600"
# 3: known_hosts exists
run_test "[ -f /root/.ssh/known_hosts ]" "root known_hosts exists"
# 4: contains github.com
run_test "grep -q '^github\\.com ' /root/.ssh/known_hosts" "known_hosts contains github.com"

#–––– Summary ––––
echo ""
[ "$fails" -eq 0 ] && echo "✅ All $tests tests passed." || echo "❌ $fails of $tests tests failed."
exit $fails
