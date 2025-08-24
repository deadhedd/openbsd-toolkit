#!/usr/bin/env bash
# obsidian-client-ubuntu-setup.sh
# v0.4.0 — install Obsidian .deb, side-load obsidian-git, wire Git remote, and SSH key setup (owner-safe)
# Author: deadhedd
set -ex

# -------------------- config (via flags) --------------------
VAULT_PATH=""
OWNER_USER=""
REMOTE_URL=""
BRANCH="main"

SSH_HOST=""         # optional; auto-derived from REMOTE_URL if omitted
SSH_PORT="22"
ACCEPT_HOSTKEY="1"  # --no-accept-hostkey to skip ssh-keyscan

SSH_KEY_PATH=""     # default -> /home/<owner>/.ssh/id_ed25519
SSH_GENERATE="0"    # --ssh-generate to create key if missing
SSH_COPY_ID="0"     # --ssh-copy-id to copy pubkey to remote

PUSH_INITIAL="0"    # --push-initial to seed a first commit/push if empty

# -------------------- helpers --------------------
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
  local user=""
  if [[ "$url" =~ ^ssh:// ]]; then
    user="$(printf '%s' "$url" | sed -E 's#^ssh://([^@]+)@[^:/]+(:[0-9]+)?/.*#\1#')"
    echo "$user"
    return 0
  fi
  # scp-like: user@host:path or host:path (no user)
  if [[ "$url" =~ @ ]]; then
    user="$(printf '%s' "$url" | sed -E 's#^([^@]+)@[^:]+:.*#\1#')"
    echo "$user"
    return 0
  fi
  echo ""  # unknown
}

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

  su_exec "$owner" git -C "$vault" ls-remote --heads origin >/dev/null
}

maybe_initial_push() {
  local owner="$1" vault="$2" branch="$3"
  [ "$PUSH_INITIAL" = "1" ] || return 0

  if ! su_exec "$owner" git -C "$vault" rev-parse --verify HEAD >/dev/null 2>&1; then
    if ! su_exec "$owner" git -C "$vault" config user.email >/dev/null 2>&1; then
      echo "Skipping initial push: set local Git identity first (git -C \"$vault\" config user.name 'Name'; git config user.email you@example.com)."
      return 0
    fi
    su_exec "$owner" bash -c "git -C \"$vault\" add -A && git -C \"$vault\" commit -m 'Initial commit' || true"
  fi

  su_exec "$owner" git -C "$vault" push -u origin "$branch" || true
}

ensure_upstream() {
  local owner="$1" vault="$2" branch="$3"

  local curr
  curr="$(su_exec "$owner" git -C "$vault" rev-parse --abbrev-ref HEAD)"

  if su_exec "$owner" git -C "$vault" rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
    return 0
  fi

  if su_exec "$owner" git -C "$vault" ls-remote --exit-code --heads origin "refs/heads/$curr" >/dev/null 2>&1; then
    su_exec "$owner" git -C "$vault" branch --set-upstream-to="origin/$curr" "$curr"
  else
    su_exec "$owner" git -C "$vault" push -u origin "$curr"
  fi
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
    # generate ed25519 key with no passphrase (simple automation default)
    su_exec "$owner" ssh-keygen -t ed25519 -N "" -f "$key_path" -C "${owner}@obsidian-client"
  fi
  # Tighten perms just in case
  su_exec "$owner" chmod 600 "$key_path"
  su_exec "$owner" chmod 644 "${key_path}.pub" 2>/dev/null || true
}

copy_ssh_key_to_remote() {
  local owner="$1" key_path="$2" user_at_host="$3" port="$4"
  [ -n "$user_at_host" ] || { echo "Cannot copy key: user@host unknown." >&2; return 1; }
  ensure_ssh_dir "$owner"
  # ssh-copy-id uses -i for the public key and -p for port
  su_exec "$owner" ssh-copy-id -i "${key_path}.pub" -p "$port" "$user_at_host"
}

# -------------------- args --------------------
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
      --help|-h)
        cat <<EOF
Usage: sudo $0 --vault /path/to/Vault --owner USER --remote-url <ssh_url> [options]

Required:
  --vault PATH            Vault directory (created if missing)
  --owner USER            Files will be created/edited as this user
  --remote-url URL        Git remote (e.g. git@server:obsidian/main.git or ssh://git@server:2222/repos/main.git)

Options:
  --branch NAME           Default branch name (default: main)
  --ssh-host HOST         SSH host for known_hosts (auto-derived from remote if omitted)
  --ssh-port PORT         SSH port (default: 22; auto-derived from ssh:// URL if present)
  --no-accept-hostkey     Skip ssh-keyscan/known_hosts pinning
  --ssh-key-path PATH     SSH key path (default: /home/<owner>/.ssh/id_ed25519)
  --ssh-generate          Generate an ed25519 key if missing (no passphrase)
  --ssh-copy-id           Copy the public key to remote (user/host derived from remote URL)
  --push-initial          If repo is empty, make an initial commit and push -u origin <branch>

EOF
        exit 0 ;;
      *) echo "Unknown arg: $1" >&2; exit 9 ;;
    esac
  done

  [ -n "$VAULT_PATH" ] || { echo "Missing required --vault" >&2; exit 8; }
  [ -n "$OWNER_USER" ] || { echo "Missing required --owner" >&2; exit 8; }
  id "$OWNER_USER" >/dev/null 2>&1 || { echo "User '$OWNER_USER' does not exist" >&2; exit 8; }
  [ -n "$REMOTE_URL" ] || { echo "Missing required --remote-url" >&2; exit 8; }

  # Defaults that depend on owner
  if [ -z "$SSH_KEY_PATH" ]; then
    SSH_KEY_PATH="/home/$OWNER_USER/.ssh/id_ed25519"
  fi
}

# -------------------- main --------------------
main() {
  require_root
  parse_args "$@"
  install_prereqs

  # Create vault as the owner
  create_vault_if_missing "$VAULT_PATH" "$OWNER_USER"

  # Install Obsidian if needed
  if ! already_installed_obsidian; then
    arch="$(detect_arch)"
    deburl="$(fetch_latest_obsidian_deb_url "$arch")"
    [ -n "$deburl" ] && [ "$deburl" != "null" ] || { echo "Could not find matching Obsidian .deb for '$arch'." >&2; exit 3; }
    install_obsidian_deb "$deburl"
    echo "✅ Obsidian installed."
  else
    echo "Obsidian already installed; skipping."
  fi

  # Install & enable obsidian-git
  install_obsidian_git_plugin "$VAULT_PATH" "$OWNER_USER"

  # Derive SSH user/host/port if not provided
  if [ -z "$SSH_HOST" ]; then
    SSH_HOST="$(derive_host_from_remote "$REMOTE_URL")"
  fi
  if [[ "$REMOTE_URL" =~ ^ssh://[^/]+:[0-9]+/ ]]; then
    SSH_PORT="$(printf '%s' "$REMOTE_URL" | sed -E 's#^ssh://[^@]+@?[^:]+:([0-9]+)/.*#\1#')"
  fi
  remote_user="$(derive_user_from_remote "$REMOTE_URL")"
  user_at_host="$SSH_HOST"
  [ -n "$remote_user" ] && user_at_host="${remote_user}@${SSH_HOST}"

  # Host key pinning (optional but convenient)
  add_hostkey_if_needed "$OWNER_USER" "$SSH_HOST" "$SSH_PORT"

  # Ensure SSH key exists (if asked), and optionally copy it to server
  if [ "$SSH_GENERATE" = "1" ] || [ "$SSH_COPY_ID" = "1" ]; then
    ensure_ssh_key "$OWNER_USER" "$SSH_KEY_PATH" || true
    if [ "$SSH_COPY_ID" = "1" ]; then
      copy_ssh_key_to_remote "$OWNER_USER" "$SSH_KEY_PATH" "$user_at_host" "$SSH_PORT"
    fi
  fi

  # Wire repo + remote and verify reachability
  ensure_repo_and_remote "$OWNER_USER" "$VAULT_PATH" "$REMOTE_URL" "$BRANCH"

  # Optional first push, then guarantee upstream is set
  maybe_initial_push "$OWNER_USER" "$VAULT_PATH" "$BRANCH"
  ensure_upstream "$OWNER_USER" "$VAULT_PATH" "$BRANCH"

  echo "✅ Git remote set to: $REMOTE_URL (branch: $BRANCH)"
  if [ "$SSH_COPY_ID" = "1" ]; then
    echo "✅ SSH key copied to: $user_at_host (port $SSH_PORT)"
  fi
  echo "All done."
}

main "$@"
