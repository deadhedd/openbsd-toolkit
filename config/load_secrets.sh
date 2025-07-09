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

# 5) Load file-based SSH keys into env vars (if specified)
for user in GIT OBS; do
  pk_file_var="${user}_SSH_PRIVATE_KEY_FILE"
  pub_file_var="${user}_SSH_PUBLIC_KEY_FILE"

  # Load private key content
  if [ -n "${!pk_file_var}" ] && [ -f "${!pk_file_var}" ]; then
    export "${user}_SSH_PRIVATE_KEY"="$(< "${!pk_file_var}")"
  fi

  # Load public key content
  if [ -n "${!pub_file_var}" ] && [ -f "${!pub_file_var}" ]; then
    export "${user}_SSH_PUBLIC_KEY"="$(< "${!pub_file_var}")"
  fi
done

