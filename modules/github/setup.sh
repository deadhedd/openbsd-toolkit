#!/bin/sh
#
# modules/github/setup.sh — Configure deploy key & bootstrap local repo
# Author: deadhedd
# Version: 1.0.0
# Updated: 2025-08-02
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

# -----------------------------------------------------------------------------
# Idempotency helpers (commented out until dry-run/rollback is implemented)
# -----------------------------------------------------------------------------
# DRY_RUN="false"
# ROLLBACK_CMDS=""
# run_cmd() {
#   _cmd="$1"
#   _rollback="$2"
#   if [ "$DRY_RUN" = "true" ]; then
#     printf '[DRY RUN] %s\n' "$_cmd"
#   else
#     eval "$_cmd"
#     ROLLBACK_CMDS="$_rollback\n$ROLLBACK_CMDS"
#   fi
# }
# safe_append_line() {
#   _file="$1"
#   _line="$2"
#   grep -Fqx "$_line" "$_file" 2>/dev/null && return 0
#   _tmp="$(mktemp)"
#   [ -f "$_file" ] && cp "$_file" "$_tmp"
#   printf '%s\n' "$_line" >> "$_tmp"
#   mv "$_tmp" "$_file"
# }
# safe_replace_line() {
#   _file="$1"
#   _pattern="$2"
#   _replacement="$3"
#   _tmp="$(mktemp)"
#   sed "s|$_pattern|$_replacement|" "$_file" > "$_tmp"
#   cmp -s "$_tmp" "$_file" || mv "$_tmp" "$_file"
#   rm -f "$_tmp"
# }
# safe_write() {
#   _file="$1"
#   _tmp="$(mktemp)"
#   cat > "$_tmp"
#   if ! cmp -s "$_tmp" "$_file" 2>/dev/null; then
#     mv "$_tmp" "$_file"
#   else
#     rm -f "$_tmp"
#   fi
# }
# rollback() {
#   printf '%s' "$ROLLBACK_CMDS" | while IFS= read -r _rb; do
#     [ -n "$_rb" ] && eval "$_rb"
#   done
# }
# trap rollback EXIT

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

# TODO: Idempotency: State detection
# TODO: Idempotency: rollback handling and dry-run mode
# run_cmd "mkdir -p /root/.ssh" "rmdir /root/.ssh"
mkdir -p /root/.ssh
# TODO: Idempotency: State detection
# TODO: Idempotency: rollback handling and dry-run mode
# run_cmd "cp \"$DEPLOY_KEY\" /root/.ssh/id_ed25519" "rm -f /root/.ssh/id_ed25519"
cp "$DEPLOY_KEY" /root/.ssh/id_ed25519
# TODO: Idempotency: Rollback handling and dry-run mode
# run_cmd "chmod 600 /root/.ssh/id_ed25519" "chmod 000 /root/.ssh/id_ed25519"
chmod 600 /root/.ssh/id_ed25519

# TODO: Idempotency: State detection
# TODO: Idempotency: safe editing or replace+template with checksum
# TODO: Idempotency: rollback handling and dry-run mode
# run_cmd "ssh-keyscan github.com >> /root/.ssh/known_hosts" "sed -i '/github.com/d' /root/.ssh/known_hosts"
# safe_append_line /root/.ssh/known_hosts "$(ssh-keyscan github.com)"
# tmp_hosts="$(mktemp)"
# cat /root/.ssh/known_hosts > "$tmp_hosts" 2>/dev/null || true
# ssh-keyscan github.com >> "$tmp_hosts"
# old_sum="$(sha256 -q /root/.ssh/known_hosts 2>/dev/null || true)"
# new_sum="$(sha256 -q "$tmp_hosts")"
# [ "$old_sum" = "$new_sum" ] || mv "$tmp_hosts" /root/.ssh/known_hosts
# rm -f "$tmp_hosts"
ssh-keyscan github.com >> /root/.ssh/known_hosts

: "LOCAL_DIR=$LOCAL_DIR"       # ensure variable is set
: "GITHUB_REPO=$GITHUB_REPO"   # ensure variable is set

[ -n "$LOCAL_DIR" ]   || { echo "ERROR: LOCAL_DIR not set" >&2; exit 1; }
[ -n "$GITHUB_REPO" ] || { echo "ERROR: GITHUB_REPO not set" >&2; exit 1; }

##############################################################################
# 5) Repo bootstrap
##############################################################################

# TODO: Idempotency: State detection
# [ -d "$LOCAL_DIR/.git" ] || git clone "$GITHUB_REPO" "$LOCAL_DIR"  # example for TODO above
# TODO: Idempotency: rollback handling and dry-run mode
# run_cmd "git clone \"$GITHUB_REPO\" \"$LOCAL_DIR\"" "rm -rf \"$LOCAL_DIR\""
git clone "$GITHUB_REPO" "$LOCAL_DIR"

echo "github: GitHub configuration complete!"
