#!/bin/sh
# test_obsidian_git_client.sh
# Assumes setup_obsidian_git_client.sh has just run.

# 0) Load config from secrets.env
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SECRETS="$SCRIPT_DIR/../config/secrets.env"  # Adjust if needed
if [ ! -f "$SECRETS" ]; then
  echo "❌ secrets.env not found at $SECRETS"
  exit 1
fi
set -a
# shellcheck source=/dev/null
. "$SECRETS"
set +a

# 1) Test helper
run_test() {
  if eval "$1"; then
    echo "ok - $2"
  else
    echo "not ok - $2"
  fi
}

# 2) Derived paths
BARE_REPO="/home/${GIT_USER}/vaults/${VAULT}.git"
WORK_TREE="/home/${OBS_USER}/vaults/${VAULT}"
LOCAL_VAULT="$HOME/${VAULT}"

# 3) SSH agent & key
run_test "ssh-add -l | grep -q id_ed25519" \
         "ssh-agent running and id_ed25519 loaded"

# 4) known_hosts entry
run_test "grep -q \"$SERVER\" ~/.ssh/known_hosts" \
         "known_hosts contains $SERVER"

# 5) local git repo exists
run_test "[ -d \"$LOCAL_VAULT/.git\" ]" \
         "local vault is a Git repo"

# 6) remote bare repo exists
run_test "ssh ${GIT_USER}@${SERVER} [ -d \"$BARE_REPO\" ]" \
         "remote bare repo exists"

# 7) post-receive hook is executable
run_test "ssh ${GIT_USER}@${SERVER} [ -x \"$BARE_REPO/hooks/post-receive\" ]" \
         "post-receive hook is present and executable"

# 8) can pull without password
run_test "ssh -o BatchMode=yes ${GIT_USER}@${SERVER} git -C \"$LOCAL_VAULT\" pull origin" \
         "git pull succeeds over SSH"

# 9) can push a dummy commit
cd "$LOCAL_VAULT" || exit 1
echo "# test $(date +%s)" >> test-sync.md
git add test-sync.md
git commit -m "TDD sync test"
run_test "git push origin HEAD" \
         "git push succeeds over SSH"
