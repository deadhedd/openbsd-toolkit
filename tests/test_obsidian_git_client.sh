#!/bin/sh
# test_obsidian_git_client.sh
# Assumes setup_obsidian_git_client.sh has just run.

#-------------------------------------------------------------------------------
# 0) Load secrets and config
SCRIPT_DIR="$(cd "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$PROJECT_ROOT/config/load_secrets.sh"

# Fail early if any required secret isn’t set
: "${KEY_NAME:?KEY_NAME must be set in secrets.env}"
: "${GIT_USER:?GIT_USER must be set in secrets.env}"
: "${OBS_USER:?OBS_USER must be set in secrets.env}"
: "${SERVER:?SERVER must be set in secrets.env}"
: "${VAULT:?VAULT must be set in secrets.env}"
#-------------------------------------------------------------------------------

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

# 3) Plugin installation
run_test "[ -d \"$HOME/.obsidian/plugins/obsidian-git\" ]" \
         "obsidian-git plugin directory exists"

# 4) SSH agent & key loaded
run_test "ssh-add -l | grep -q \"$KEY_NAME\"" \
         "ssh-agent running and \"$KEY_NAME\" loaded"

# 5) Public key on server
run_test "ssh -o BatchMode=yes ${GIT_USER}@${SERVER} \"grep -q '$(cat ~/.ssh/${KEY_NAME}.pub)' ~/.ssh/authorized_keys\"" \
         "public key present in server’s authorized_keys"

# 6) Local Git repo exists
run_test "[ -d \"$LOCAL_VAULT/.git\" ]" \
         "local vault is a Git repo"

# 7) Remote bare repo exists
run_test "ssh ${GIT_USER}@${SERVER} [ -d \"$BARE_REPO\" ]" \
         "remote bare repo exists"

# 8) Post‑receive hook is executable
run_test "ssh ${GIT_USER}@${SERVER} [ -x \"$BARE_REPO/hooks/post-receive\" ]" \
         "post-receive hook is present and executable"

# 9) Git remote configuration
run_test "cd \"$LOCAL_VAULT\" && \
          git remote get-url origin | \
          grep -q \"${GIT_USER}@${SERVER}:${BARE_REPO}\"" \
         "git remote 'origin' correctly set"

# 10) Can pull without password
run_test "ssh -o BatchMode=yes ${GIT_USER}@${SERVER} git -C \"$LOCAL_VAULT\" pull origin" \
         "git pull succeeds over SSH"

# 11) Can fetch & push without password (dry‑run)
run_test "cd \"$LOCAL_VAULT\" && \
          GIT_SSH_COMMAND='ssh -o BatchMode=yes' \
          git fetch --dry-run origin" \
         "git fetch succeeds without password"
run_test "cd \"$LOCAL_VAULT\" && \
          GIT_SSH_COMMAND='ssh -o BatchMode=yes' \
          git push --dry-run origin HEAD:HEAD" \
         "git push succeeds without password"

# 12) Known hosts entry management
run_test "grep -q \"$SERVER\" \"$HOME/.ssh/known_hosts\"" \
         "known_hosts contains \"$SERVER\""
run_test "ssh-keygen -f \"$HOME/.ssh/known_hosts\" -R \"$SERVER\" >/dev/null 2>&1 && \
          ssh -o StrictHostKeyChecking=no ${GIT_USER}@${SERVER} exit" \
         "known_hosts entry can be regenerated automatically"

# 13) SSH key files & permissions for local user
run_test "[ -f \"$HOME/.ssh/${KEY_NAME}\" ]" \
         "private key exists at ~/.ssh/${KEY_NAME}"
run_test "[ \"\$(stat -c '%a' \"$HOME/.ssh/${KEY_NAME}\")\" = \"600\" ]" \
         "private key permissions are 600"
run_test "[ -f \"$HOME/.ssh/${KEY_NAME}.pub\" ]" \
         "public key exists at ~/.ssh/${KEY_NAME}.pub"
run_test "[ \"\$(stat -c '%a' \"$HOME/.ssh/${KEY_NAME}.pub\")\" = \"644\" ]" \
         "public key permissions are 644"

# 14) Dummy commit push test
cd "$LOCAL_VAULT" || exit 1
echo "# test $(date +%s)" >> test-sync.md
git add test-sync.md
git commit -m "TDD sync test"
run_test "git push origin HEAD" \
         "git push succeeds over SSH"

