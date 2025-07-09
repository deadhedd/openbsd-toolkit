#!/bin/sh
# config/load-secrets.sh

# 1) Find project root & config dir
script_dir=$(cd "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(cd "$script_dir"/.. && pwd)
CONFIG_DIR="$PROJECT_ROOT/config"

# 2) Point to example & real secrets
EXAMPLE="$CONFIG_DIR/secrets.env.example"
SECRETS="$CONFIG_DIR/secrets.env"

# 3) Bootstrap if missing
if [ ! -f "$SECRETS" ]; then
  cp "$EXAMPLE" "$SECRETS"
  echo "⚠️  Created '$SECRETS' from example. Please edit it and re-run." >&2
  exit 1
fi

# 4) Export all vars from secrets.env
set -a
# shellcheck source=/dev/null
. "$SECRETS"
set +a

# 5) Default to the single-client keypair if no per-account override
: "${SSH_PRIVATE_KEY_FILE:=$CONFIG_DIR/ssh/id_ed25519}"
: "${SSH_PUBLIC_KEY_FILE:=$CONFIG_DIR/ssh/id_ed25519.pub}"

# 6) Load each account’s key into an env var
for user in GIT OBS ADMIN ROOT; do
  # Determine which file‑var to read, falling back to SSH_PRIVATE_KEY_FILE
  pk_file_var="${user}_SSH_PRIVATE_KEY_FILE"
  pub_file_var="${user}_SSH_PUBLIC_KEY_FILE"

  # Resolve private key file path
  eval "pk_path=\"\${$pk_file_var:-\$SSH_PRIVATE_KEY_FILE}\""
  if [ -f "$pk_path" ]; then
    eval "${user}_SSH_PRIVATE_KEY=\"\$(cat \"$pk_path\")\""
    export "${user}_SSH_PRIVATE_KEY"
  fi

  # Resolve public key file path
  eval "pub_path=\"\${$pub_file_var:-\$SSH_PUBLIC_KEY_FILE}\""
  if [ -f "$pub_path" ]; then
    eval "${user}_SSH_PUBLIC_KEY=\"\$(cat \"$pub_path\")\""
    export "${user}_SSH_PUBLIC_KEY"
  fi
done

