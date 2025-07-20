#!/bin/sh
# config/load-secrets.sh

# 1) Determine the project root (one level above config/)
PROJECT_ROOT="$(cd "$(dirname -- "$0")"/.. && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"

# 2) Define locations for example and real secrets
EXAMPLE="$CONFIG_DIR/secrets.env.example"
SECRETS="$CONFIG_DIR/secrets.env"

# 3) Bootstrap real secrets from example if missing
if [ ! -f "$SECRETS" ]; then
  cp "$EXAMPLE" "$SECRETS"
  echo "⚠️  Created '$SECRETS' from example. Please edit it and re-run." >&2
  exit 1
fi

# 4) Export all vars from the secrets file
set -a
# shellcheck source=/dev/null
. "$SECRETS"
set +a
