#!/bin/sh
#
# test.sh — Validate GitHub deploy key & repo bootstrap (github module)

set -x

# 1) Locate project root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 2) Load secrets
. "$PROJECT_ROOT/config/load_secrets.sh"

# 3) Default fallbacks (if secrets aren’t set)
local_dir="${LOCAL_DIR:-/root/openbsd-server}"
github_repo="${GITHUB_REPO:-git@github.com:deadhedd/openbsd-server.git}"

# 4) Tests

# 4.1 Root .ssh directory exists
[ -d /root/.ssh ]

# 4.2 Deploy key present and mode is 600
[ -f /root/.ssh/id_ed25519 ]
stat -f '%Lp' /root/.ssh/id_ed25519 | grep -q '^600$'

# 4.3 known_hosts exists and contains GitHub
[ -f /root/.ssh/known_hosts ]
grep -q '^github\.com ' /root/.ssh/known_hosts

# 4.4 Repository was cloned
[ -d "$local_dir/.git" ]

# 4.5 Remote origin set correctly in config
grep -q "url = $github_repo" "$local_dir/.git/config"

echo "✅ github tests passed."

