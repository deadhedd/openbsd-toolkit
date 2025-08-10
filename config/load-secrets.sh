#!/bin/sh
#
# config/load-secrets.sh — Export variables from secrets.env for other scripts
# Author: deadhedd
# Version: 1.0.1
# Updated: 2025-08-10
#
# Usage: . "$PROJECT_ROOT/config/load-secrets.sh" <ModuleName>   # must be sourced
#
# Description:
#   Ensures config/secrets.env exists (copies from example if missing) and then
#   exports KEY=VALUE pairs for the requested module using `set -a`. Exits
#   after creating the file so the caller can prompt the user to edit it.
#
# Deployment considerations:
#   Handling secrets is more difficult when cloning the repo
#   directly onto a freshly installed server instead of preparing it offline
#   and mounting via USB. Some assumptions (like pre-editing secrets.env) may
#   break in unattended remote install workflows.
#
# See also:
#   - config/secrets.env.example

##############################################################################
# 0) Resolve paths
##############################################################################

PROJECT_ROOT="$(cd "$(dirname -- "$0")"/../.. && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"

EXAMPLE="$CONFIG_DIR/secrets.env.example"
SECRETS="$CONFIG_DIR/secrets.env"
MODULE="$1"

##############################################################################
# 1) Bootstrap secrets file if missing
##############################################################################

if [ ! -f "$SECRETS" ]; then
  # cmp -s "$EXAMPLE" "$SECRETS" || cp "$EXAMPLE" "$SECRETS"
  cp "$EXAMPLE" "$SECRETS"  # TODO: use state detection for idempotency
  echo "Created '$SECRETS' from example. Please edit it and re-run." >&2
  exit 1
fi

##############################################################################
# 2) Export vars for requested module
##############################################################################

if [ -z "$MODULE" ]; then
  echo "Usage: . \"$PROJECT_ROOT/config/load-secrets.sh\" <ModuleName>" >&2
  return 1 2>/dev/null || exit 1
fi

tmpfile="$(mktemp)"
awk -v section="$MODULE" '
  /^#=+/ {
    getline header
    gsub(/^#[[:space:]]*/, "", header)
    gsub(/^Module:[[:space:]]*/, "", header)
    sub(/[[:space:]]*$/, "", header)
    getline
    in_section = (header == section)
    next
  }
  in_section {print}
' "$SECRETS" > "$tmpfile"

if [ ! -s "$tmpfile" ]; then
  echo "No section for '$MODULE' found in '$SECRETS'" >&2
  rm -f "$tmpfile"
  return 1 2>/dev/null || exit 1
fi

set -a
# shellcheck source=/dev/null
. "$tmpfile"
set +a
rm -f "$tmpfile"
