#!/bin/sh
# scripts/load-secrets.sh

# where this script lives
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

# example (tracked) vs real (gitignored)
EXAMPLE="${SCRIPT_DIR}/secrets.env.example"
SECRETS="${SCRIPT_DIR}/secrets.env"

# if they haven’t yet made their real secrets file, bootstrap it
if [ ! -f "$SECRETS" ]; then
  cp "$EXAMPLE" "$SECRETS"
  echo "⚠️  Created '$SECRETS' from example. Please edit it and re-run."
  exit 1
fi

# export all vars in it
set -a
  # shellcheck source=/dev/null
  . "$SECRETS"
set +a
