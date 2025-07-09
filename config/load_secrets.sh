#!/bin/sh
# config/load-secrets.sh

# 1) Determine the project root (one level above config/)
script_dir=$(dirname -- "$0")
PROJECT_ROOT=$(cd "$script_dir"/.. && pwd)
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

# 5) Load file-based SSH keys into env vars (POSIX compliant)
for user in GIT OBS; do
  pk_file_var="${user}_SSH_PRIVATE_KEY_FILE"
  pub_file_var="${user}_SSH_PUBLIC_KEY_FILE"

  # Resolve private key file path
  eval "pk_file=\${$pk_file_var}"
  if [ -n "$pk_file" ] && [ -f "$pk_file" ]; then
    eval "${user}_SSH_PRIVATE_KEY=\$(cat \"$pk_file\")"
    export "${user}_SSH_PRIVATE_KEY"
  fi

  # Resolve public key file path
  eval "pub_file=\${$pub_file_var}"
  if [ -n "$pub_file" ] && [ -f "$pub_file" ]; then
    eval "${user}_SSH_PUBLIC_KEY=\$(cat \"$pub_file\")"
    export "${user}_SSH_PUBLIC_KEY"
  fi
done

