#!/bin/sh
# config/load-secrets.sh

##############################################################################
# 0) Resolve paths
##############################################################################

PROJECT_ROOT="$(cd "$(dirname -- "$0")"/../.. && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"

EXAMPLE="$CONFIG_DIR/secrets.env.example"
SECRETS="$CONFIG_DIR/secrets.env"

##############################################################################
# 1) Bootstrap secrets file if missing
##############################################################################

if [ ! -f "$SECRETS" ]; then
  cp "$EXAMPLE" "$SECRETS"
  echo "Created '$SECRETS' from example. Please edit it and re-run." >&2
  exit 1
fi

##############################################################################
# 2) Export all vars from secrets.env
##############################################################################

set -a
# shellcheck source=/dev/null
. "$SECRETS"
set +a
