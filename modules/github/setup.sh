#!/bin/sh
#
# modules/github/setup.sh — Configure deploy key & bootstrap local repo
# Author: deadhedd
# Version: 1.0.0
# Updated: 2025-07-28
#
# Usage: sh setup.sh [--debug[=FILE]] [-h]
#
# Description:
#   Copies the deploy key into /root/.ssh, hard-locks its permissions, adds
#   GitHub to known_hosts, validates required secrets, and clones the remote
#   repository to LOCAL_DIR for Git-backed Obsidian sync.
#
# Deployment considerations:
#   Requires these variables (exported via config/load-secrets.sh):
#     • LOCAL_DIR     — target clone path
#     • GITHUB_REPO   — git@github.com:… or https://… URL
#   Also expects config/deploy_key to exist before execution.
#
# Security note:
#   Enabling the --debug flag will log all executed commands *and their expanded
#   values* (via `set -vx`), including any exported secrets or credentials.
#   Use caution when sharing or retaining debug logs.
#
# See also:
#   - modules/github/test.sh
#   - logs/logging.sh
#   - config/load-secrets.sh

##############################################################################
# 0) Resolve Paths
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export PROJECT_ROOT

##############################################################################
# 1) Help & banned flags prescan
##############################################################################

show_help() {
  cat <<EOF
  Usage: sh $(basename "$0") [options]

  Description:
    Configure GitHub deploy key and initialize bare repo

  Options:
    -h, --help        Show this help message and exit
    -d, --debug       Enable debug/xtrace and write a log file
EOF
}
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      show_help
      exit 0
      ;;
    -l|--log|-l=*|--log=*)
      printf '%s\n' "This script no longer supports --log. Did you mean --debug?" >&2
      exit 2
      ;;
  esac
done

##############################################################################
# 2) Logging init
##############################################################################

# shellcheck source=logs/logging.sh
. "$PROJECT_ROOT/logs/logging.sh"
module_name="$(basename "$SCRIPT_DIR")"
start_logging_if_debug "setup-$module_name" "$@"

##############################################################################
# 3) Inputs (secrets & constants) + validation
##############################################################################

. "$PROJECT_ROOT/config/load-secrets.sh"
DEPLOY_KEY="$PROJECT_ROOT/config/deploy_key"

[ -f "$DEPLOY_KEY" ] || { echo "ERROR: deploy_key not found at $DEPLOY_KEY" >&2; exit 1; }

##############################################################################
# 4) SSH setup (keys & known_hosts)
##############################################################################

mkdir -p /root/.ssh
cp "$DEPLOY_KEY" /root/.ssh/id_ed25519
chmod 600 /root/.ssh/id_ed25519

ssh-keyscan github.com >> /root/.ssh/known_hosts

: "LOCAL_DIR=$LOCAL_DIR"       # ensure variable is set
: "GITHUB_REPO=$GITHUB_REPO"   # ensure variable is set

[ -n "$LOCAL_DIR" ]   || { echo "ERROR: LOCAL_DIR not set" >&2; exit 1; }
[ -n "$GITHUB_REPO" ] || { echo "ERROR: GITHUB_REPO not set" >&2; exit 1; }

##############################################################################
# 5) Repo bootstrap
##############################################################################

git clone "$GITHUB_REPO" "$LOCAL_DIR"

echo "github: GitHub configuration complete!"
