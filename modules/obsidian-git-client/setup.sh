#!/usr/bin/env bash
# obsidian-client-ubuntu-setup.sh
# v0.5.0 — install Obsidian .deb, side-load obsidian-git, wire Git remote, SSH key “just works”
# Author: deadhedd
set -e
[ -n "$BASH_VERSION" ] || { echo "Please run with bash: sudo bash $0 ..." >&2; exit 1; }

##############################################################################
# 0) Resolve paths
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export PROJECT_ROOT

##############################################################################
# 1) Help & banned flags prescan
##############################################################################

show_help() {
  cat <<EOF
Usage: sudo bash $(basename "$0") --vault /path/to/Vault --owner USER --remote-url <ssh_url> [options]

Required:
  --vault PATH            Vault directory (created if missing)
  --owner USER            Files will be created/edited as this user
  --remote-url URL        Git remote (e.g. git@server:/home/git/vaults/Main.git)

Options:
  --branch NAME           Branch name to use if initializing (default: main)
  --ssh-host HOST         SSH host for known_hosts (auto-derived from remote if omitted)
  --ssh-port PORT         SSH port (default: 22; auto-derived from ssh:// URL if present)
  --no-accept-hostkey     Skip ssh-keyscan/known_hosts pinning
  --ssh-key-path PATH     SSH private key path (default: /home/<owner>/.ssh/id_ed25519)
  --ssh-generate          Generate an ed25519 key at the path if missing (no passphrase)
  --ssh-copy-id           Copy the public key to the remote (user/host from remote URL)
  --push-initial          If repo is empty, make an initial commit and push -u origin <branch>
  --initial-sync MODE     First sync policy: remote-wins | local-wins | merge | none
  --launch                Launch Obsidian once to register the vault (default)
  --no-launch             Skip launching Obsidian; prints command to run manually
  --debug[=FILE]          Enable debug logging (writes log to FILE if provided)
  --log[=FILE]            Force logging even without debug mode
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

. "$PROJECT_ROOT/config/load-secrets.sh" "Base System"
. "$PROJECT_ROOT/config/load-secrets.sh" "Obsidian Git Host"
. "$PROJECT_ROOT/config/load-secrets.sh" "Obsidian Git Client"
. "$PROJECT_ROOT/config/load-secrets.sh" "SSH"
: "${CLIENT_OWNER:?CLIENT_OWNER must be set in secrets}"
: "${CLIENT_REMOTE_URL:?CLIENT_REMOTE_URL must be set in secrets}"
if [ -n "${CLIENT_VAULT_PATH:-}" ]; then
  VAULT_PATH="$CLIENT_VAULT_PATH"
else
  : "${CLIENT_VAULT:?CLIENT_VAULT must be set in secrets}"
  VAULT_PATH="/home/$CLIENT_OWNER/$CLIENT_VAULT"
fi
OWNER_USER="$CLIENT_OWNER"
REMOTE_URL="$CLIENT_REMOTE_URL"
BRANCH="${CLIENT_BRANCH:-main}"

SSH_HOST="$CLIENT_SSH_HOST"         # optional; auto-derived from REMOTE_URL if omitted
SSH_PORT="${CLIENT_SSH_PORT:-22}"
ACCEPT_HOSTKEY="${CLIENT_ACCEPT_HOSTKEY:-1}"  # --no-accept-hostkey to skip ssh-keyscan

SSH_KEY_PATH="$CLIENT_SSH_KEY_PATH"     # default -> from SSH module
if [ -z "$SSH_KEY_PATH" ]; then
  SSH_KEY_PATH="$PROJECT_ROOT/$SSH_KEY_DIR/$SSH_PRIVATE_KEY_DEFAULT"
fi
SSH_GENERATE="${CLIENT_SSH_GENERATE:-0}"    # --ssh-generate to create key if missing
SSH_COPY_ID="${CLIENT_SSH_COPY_ID:-0}"     # --ssh-copy-id to copy pubkey to remote

PUSH_INITIAL="${CLIENT_PUSH_INITIAL:-0}"    # --push-initial to seed a first commit/push if empty
INITIAL_SYNC="${CLIENT_INITIAL_SYNC:-none}" # --initial-sync: none | remote-wins | local-wins | merge
LAUNCH="${CLIENT_LAUNCH:-1}"            # --no-launch to skip opening Obsidian once

##############################################################################
# Helpers
##############################################################################
require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Please run as root: sudo $0" >&2
    exit 1
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 2 ;;
  esac
}

install_prereqs() {
  apt-get update -y
  apt-get install -y --no-install-recommends curl jq unzip git openssh-client
}

already_installed_obsidian() {
  dpkg -s obsidian >/dev/null 2>&1
}

fetch_latest_obsidian_deb_url() {
  local arch="$1"
  curl -fsSL https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest \
  | jq -r --arg arch "$arch" '
      .assets[] | select(.name | test("^obsidian_.*_\\Q"+$arch+"\\E\\.deb$")) | .browser_download_url
    ' | head -n1
}

install_obsidian_deb() {
  local url="$1"
  local tmpdeb
  tmpdeb="$(mktemp --suffix=.deb)"
  echo "Downloading Obsidian: $url"
  curl -fL "$url" -o "$tmpdeb"
  apt-get install -y "$tmpdeb"
  rm -f "$tmpdeb"
}

# su_exec <owner> <cmd...>
su_exec() {
  local user="$1"; shift
  sudo -u "$user" -- "$@"
}

# -------------------- obsidian-git plugin --------------------
fetch_latest_obsidian_git_zip_url() {
  curl -fsSL https://api.github.com/repos/Vinzent03/obsidian-git/releases/latest \
  | jq -r '
      .assets[]
      | select(.name | endswith(".zip"))
      | .browser_download_url
    ' | head -n1
}

enable_plugin_in_vault() {
  local vault="$1" plugin_id="$2" owner="$3"
  local cfg="$vault/.obsidian/community-plugins.json"

  su_exec "$owner" mkdir -p "$(dirname "$cfg")"
  if ! su_exec "$owner" test -f "$cfg"; then
    su_exec "$owner" bash -c "echo '[]' > \"$cfg\""
  fi

  su_exec "$owner" bash -c "
    tmpfile=\$(mktemp)
    jq --arg id '$plugin_id' '( . | index(\$id) ) as \$idx | if \$idx == null then . + [\$id] else . end' \"$cfg\" > \"\$tmpfile\" &&
    mv \"\$tmpfile\" \"$cfg\"
  "
}

install_obsidian_git_plugin() {
  local vault="$1" owner="$2"
  local plugin_id="obsidian-git"
  local plugin_dir="$vault/.obsidian/plugins/$plugin_id"

  su_exec "$owner" mkdir -p "$plugin_dir"

  local zipurl tmpzip
  zipurl="$(fetch_latest_obsidian_git_zip_url)"
  [ -n "$zipurl" ] && [ "$zipurl" != "null" ] || { echo "Could not find latest obsidian-git release zip." >&2; exit 4; }

  tmpzip="$(su_exec "$owner" mktemp --suffix=.zip | tr -d '\r\n')"
  echo "Downloading obsidian-git: $zipurl"
  su_exec "$owner" bash -c "curl -fL '$zipurl' -o '$tmpzip'"

  # Drop internal zip paths so manifest.json lands directly in plugin_dir
  su_exec "$owner" unzip -j -o "$tmpzip" -d "$plugin_dir" >/dev/null
  su_exec "$owner" rm -f "$tmpzip"

  enable_plugin_in_vault "$vault" "$plugin_id" "$owner"
  echo "✅ obsidian-git installed to: $plugin_dir"
  echo "✅ obsidian-git enabled in: $vault/.obsidian/community-plugins.json"
}

# -------------------- vault --------------------
create_vault_if_missing() {
  local vault="$1" owner="$2"
  if [ ! -d "$vault" ]; then
    install -d -m 0755 -o "$owner" -g "$owner" "$vault"
  fi
}

# -------------------- Git wiring --------------------
derive_host_from_remote() {
  local url="$1"
  local host=""
  if [[ "$url" =~ ^ssh:// ]]; then
    host="$(printf '%s' "$url" | sed -E 's#^ssh://([^@]+@)?([^:/]+)(:[0-9]+)?/.*#\2#')"
    echo "$host"; return 0
  fi
  host="$(printf '%s' "$url" | sed -E 's#^[^@]*@?([^:/]+):.*#\1#')"
  echo "$host"
}

derive_user_from_remote() {
  local url="$1"
  if [[ "$url" =~ ^ssh:// ]]; then
    printf '%s' "$url" | sed -E 's#^ssh://([^@]+)@[^:/]+(:[0-9]+)?/.*#\1#'
    return 0
  fi
  if [[ "$url" =~ @ ]]; then
    printf '%s' "$url" | sed -E 's#^([^@]+)@[^:]+:.*#\1#'
    return 0
  fi
  echo ""
}

# Add known_hosts for the server
add_hostkey_if_needed() {
  local owner="$1" host="$2" port="$3"
  [ -n "$host" ] || return 0
  [ "$ACCEPT_HOSTKEY" = "1" ] || return 0

  su_exec "$owner" mkdir -p "/home/$owner/.ssh"
  su_exec "$owner" chmod 700 "/home/$owner/.ssh"
  su_exec "$owner" bash -c "touch /home/$owner/.ssh/known_hosts && chmod 600 /home/$owner/.ssh/known_hosts"

  if ! su_exec "$owner" ssh-keygen -F "$host" >/dev/null; then
    su_exec "$owner" bash -c "ssh-keyscan -p '$port' -t rsa,ecdsa,ed25519 '$host' >> /home/$owner/.ssh/known_hosts"
  fi
}

# NEW: write SSH config so this repo uses your specified key automatically
write_ssh_config_entry() {
  local owner="$1" host="$2" user="$3" port="$4" key="$5"
  [ -n "$key" ] || return 0
  su_exec "$owner" mkdir -p "/home/$owner/.ssh"
  su_exec "$owner" chmod 700 "/home/$owner/.ssh"
  su_exec "$owner" bash -c "umask 077; touch /home/$owner/.ssh/config"
  su_exec "$owner" bash -c "grep -qE '^[Hh]ost(\\s|\\s.*\\s)$host(\\s|\$)' /home/$owner/.ssh/config || cat >> /home/$owner/.ssh/config <<'CFG'
Host $host
  HostName $host
  User $user
  Port $port
  IdentityFile $key
  IdentitiesOnly yes
CFG"
  su_exec "$owner" chmod 600 "/home/$owner/.ssh/config"
}

# Force Git to use a specific key/port for SSH calls
git_ssh_env() {
  local key="$1" port="$2"
  if [ -n "$key" ]; then
    echo "ssh -i '$key' -o IdentitiesOnly=yes -p '$port'"
  else
    echo "ssh -p '$port'"
  fi
}

ensure_repo_and_remote() {
  local owner="$1" vault="$2" remote="$3" branch="$4"

  if ! su_exec "$owner" test -d "$vault/.git"; then
    su_exec "$owner" git -C "$vault" init
    su_exec "$owner" git -C "$vault" symbolic-ref HEAD "refs/heads/$branch"
  fi

  if su_exec "$owner" git -C "$vault" remote get-url origin >/dev/null 2>&1; then
    su_exec "$owner" git -C "$vault" remote set-url origin "$remote"
  else
    su_exec "$owner" git -C "$vault" remote add origin "$remote"
  fi

  # Verify connectivity using the specified key/port if provided
  if ! su_exec "$owner" env GIT_SSH_COMMAND="$(git_ssh_env "$SSH_KEY_PATH" "$SSH_PORT")" \
       git -C "$vault" ls-remote --heads origin >/dev/null 2>&1; then
    echo "Remote not reachable or not a repo. Double-check --remote-url (must point to an existing *bare* repo, usually ends with .git)." >&2
    exit 10
  fi
}

set_git_local_push_defaults() {
  local owner="$1" vault="$2"
  su_exec "$owner" git -C "$vault" config push.default current
  su_exec "$owner" git -C "$vault" config --add --bool push.autoSetupRemote true
}

maybe_initial_push() {
  local owner="$1" vault="$2" branch="$3"
  [ "$PUSH_INITIAL" = "1" ] || return 0

  if ! su_exec "$owner" git -C "$vault" rev-parse --verify HEAD >/dev/null 2>&1; then
    if ! su_exec "$owner" git -C "$vault" config user.email >/dev/null 2>&1; then
      echo "Skipping initial push: set local Git identity first (git -C \"$vault\" config user.name 'Name'; git -C \"$vault\" config user.email you@example.com)."
      return 0
    fi
    su_exec "$owner" bash -c "git -C \"$vault\" add -A && git -C \"$vault\" commit -m 'Initial commit' || true"
  fi

  su_exec "$owner" env GIT_SSH_COMMAND="$(git_ssh_env "$SSH_KEY_PATH" "$SSH_PORT")" \
    git -C "$vault" push -u origin "$branch" || true
}

# UPDATED: fetches before setting upstream; supports initial sync policy
ensure_upstream() {
  local owner="$1" vault="$2" branch="$3"

  local curr
  curr="$(su_exec "$owner" git -C "$vault" rev-parse --abbrev-ref HEAD)"

  # If upstream already set, we're done.
  if su_exec "$owner" git -C "$vault" rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
    return 0
  fi

  # Does the remote branch exist? (networked check)
  if su_exec "$owner" env GIT_SSH_COMMAND="$(git_ssh_env "$SSH_KEY_PATH" "$SSH_PORT")" \
       git -C "$vault" ls-remote --exit-code --heads origin "refs/heads/$curr" >/dev/null 2>&1; then
    # Make sure origin/$curr exists locally, then set upstream
    su_exec "$owner" env GIT_SSH_COMMAND="$(git_ssh_env "$SSH_KEY_PATH" "$SSH_PORT")" \
      git -C "$vault" fetch origin "$curr"
    su_exec "$owner" git -C "$vault" branch --set-upstream-to="origin/$curr" "$curr"

    case "$INITIAL_SYNC" in
      remote-wins)
        su_exec "$owner" git -C "$vault" reset --hard "origin/$curr"
        ;;
      local-wins)
        su_exec "$owner" env GIT_SSH_COMMAND="$(git_ssh_env "$SSH_KEY_PATH" "$SSH_PORT")" \
          git -C "$vault" push --force-with-lease -u origin "$curr"
        ;;
      merge)
        su_exec "$owner" git -C "$vault" merge --allow-unrelated-histories "origin/$curr" || true
        su_exec "$owner" env GIT_SSH_COMMAND="$(git_ssh_env "$SSH_KEY_PATH" "$SSH_PORT")" \
          git -C "$vault" push || true
        ;;
      *) : ;;
    esac
    return 0
  fi

  # Remote branch does not exist → create it and set upstream in one go
  su_exec "$owner" env GIT_SSH_COMMAND="$(git_ssh_env "$SSH_KEY_PATH" "$SSH_PORT")" \
    git -C "$vault" push -u origin "$curr"
}

# -------------------- SSH key management --------------------
ensure_ssh_dir() {
  local owner="$1"
  su_exec "$owner" mkdir -p "/home/$owner/.ssh"
  su_exec "$owner" chmod 700 "/home/$owner/.ssh"
}

ensure_ssh_key() {
  local owner="$1" key_path="$2"
  ensure_ssh_dir "$owner"
  if ! su_exec "$owner" test -f "$key_path"; then
    if [ "$SSH_GENERATE" != "1" ]; then
      echo "No SSH key at $key_path. Pass --ssh-generate to create one." >&2
      return 1
    fi
    su_exec "$owner" ssh-keygen -t ed25519 -N "" -f "$key_path" -C "${owner}@obsidian-client"
  fi
  su_exec "$owner" chmod 600 "$key_path"
  su_exec "$owner" chmod 644 "${key_path}.pub" 2>/dev/null || true
}

ensure_ssh_agent() {
  local owner="$1" key_path="$2" home="/home/$1"
  su_exec "$owner" env SSH_KEY_PATH="$key_path" HOME_DIR="$home" sh -s <<'EOF'
home="$HOME_DIR"
key="$SSH_KEY_PATH"
envfile="$home/.ssh/agent.env"
[ -r "$envfile" ] && . "$envfile" >/dev/null 2>&1
if ! ssh-add -l >/dev/null 2>&1; then
  eval "$(ssh-agent -s)"
  printf 'SSH_AUTH_SOCK=%s\nSSH_AGENT_PID=%s\nexport SSH_AUTH_SOCK SSH_AGENT_PID\n' "$SSH_AUTH_SOCK" "$SSH_AGENT_PID" > "$envfile"
  chmod 600 "$envfile"
fi
ssh-add "$key" >/dev/null
EOF
}

copy_ssh_key_to_remote() {
  local owner="$1" key_path="$2" user_at_host="$3" port="$4"
  [ -n "$user_at_host" ] || { echo "Cannot copy key: user@host unknown." >&2; return 1; }
  ensure_ssh_dir "$owner"
  su_exec "$owner" ssh-copy-id -i "${key_path}.pub" -p "$port" "$user_at_host"
}

##############################################################################
# Argument parsing
##############################################################################
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --vault) VAULT_PATH="${2:-}"; shift 2 ;;
      --owner) OWNER_USER="${2:-}"; shift 2 ;;
      --remote-url) REMOTE_URL="${2:-}"; shift 2 ;;
      --branch) BRANCH="${2:-}"; shift 2 ;;
      --ssh-host) SSH_HOST="${2:-}"; shift 2 ;;
      --ssh-port) SSH_PORT="${2:-}"; shift 2 ;;
      --no-accept-hostkey) ACCEPT_HOSTKEY="0"; shift ;;
      --ssh-key-path) SSH_KEY_PATH="${2:-}"; shift 2 ;;
      --ssh-generate) SSH_GENERATE="1"; shift ;;
      --ssh-copy-id) SSH_COPY_ID="1"; shift ;;
      --push-initial) PUSH_INITIAL="1"; shift ;;
      --initial-sync) INITIAL_SYNC="${2:-}"; shift 2 ;;
      --launch) LAUNCH="1"; shift ;;
      --no-launch) LAUNCH="0"; shift ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        echo "Unknown arg: $1" >&2
        exit 9
        ;;
    esac
  done

  [ -n "$VAULT_PATH" ] || { echo "Missing required --vault" >&2; exit 8; }
  [ -n "$OWNER_USER" ] || { echo "Missing required --owner" >&2; exit 8; }
  id "$OWNER_USER" >/dev/null 2>&1 || { echo "User '$OWNER_USER' does not exist" >&2; exit 8; }
  [ -n "$REMOTE_URL" ] || { echo "Missing required --remote-url" >&2; exit 8; }

  if [ -z "$SSH_KEY_PATH" ]; then
    SSH_KEY_PATH="/home/$OWNER_USER/.ssh/id_ed25519"
  fi
}
require_root
parse_args "$@"

##############################################################################
# 4) Packages
##############################################################################

install_prereqs

if ! already_installed_obsidian; then
  arch="$(detect_arch)"
  deburl="$(fetch_latest_obsidian_deb_url "$arch")"
  [ -n "$deburl" ] && [ "$deburl" != "null" ] || { echo "Could not find matching Obsidian .deb for '$arch'." >&2; exit 3; }
  install_obsidian_deb "$deburl"
  echo "✅ Obsidian installed."
else
  echo "Obsidian already installed; skipping."
fi

##############################################################################
# 5) Vault & plugin
##############################################################################

create_vault_if_missing "$VAULT_PATH" "$OWNER_USER"
install_obsidian_git_plugin "$VAULT_PATH" "$OWNER_USER"

##############################################################################
# 6) SSH setup
##############################################################################

if [ -z "$SSH_HOST" ]; then
  SSH_HOST="$(derive_host_from_remote "$REMOTE_URL")"
fi
if [[ "$REMOTE_URL" =~ ^ssh://[^/]+:[0-9]+/ ]]; then
  SSH_PORT="$(printf '%s' "$REMOTE_URL" | sed -E 's#^ssh://[^@]+@?[^:]+:([0-9]+)/.*#\1#')"
fi
remote_user="$(derive_user_from_remote "$REMOTE_URL")"
[ -n "$remote_user" ] || remote_user="git"
user_at_host="${remote_user}@${SSH_HOST}"

add_hostkey_if_needed "$OWNER_USER" "$SSH_HOST" "$SSH_PORT"

if [ "$SSH_GENERATE" = "1" ] || [ "$SSH_COPY_ID" = "1" ]; then
  ensure_ssh_key "$OWNER_USER" "$SSH_KEY_PATH" || true
  ensure_ssh_agent "$OWNER_USER" "$SSH_KEY_PATH"
  if [ "$SSH_COPY_ID" = "1" ]; then
    copy_ssh_key_to_remote "$OWNER_USER" "$SSH_KEY_PATH" "$user_at_host" "$SSH_PORT"
  fi
fi

write_ssh_config_entry "$OWNER_USER" "$SSH_HOST" "$remote_user" "$SSH_PORT" "$SSH_KEY_PATH"

##############################################################################
# 7) Git wiring
##############################################################################

ensure_repo_and_remote "$OWNER_USER" "$VAULT_PATH" "$REMOTE_URL" "$BRANCH"
set_git_local_push_defaults "$OWNER_USER" "$VAULT_PATH"
maybe_initial_push "$OWNER_USER" "$VAULT_PATH" "$BRANCH"
ensure_upstream "$OWNER_USER" "$VAULT_PATH" "$BRANCH"

echo "✅ Git remote set to: $REMOTE_URL (branch: $BRANCH)"
if [ "$LAUNCH" = "1" ]; then
  su_exec "$OWNER_USER" bash -lc "obsidian \"$VAULT_PATH\" --disable-gpu >/dev/null 2>&1 || true"
else
  cat <<EOF
Reminder: run the following command once to register the vault with Obsidian:
  su_exec "$OWNER_USER" bash -lc 'obsidian "$VAULT_PATH" --disable-gpu >/dev/null 2>&1 || true'
EOF
fi

echo "All done."
