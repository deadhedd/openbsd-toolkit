#!/usr/bin/env bash
# obsidian-client-ubuntu-setup.sh
# v0.2.3 — install Obsidian .deb + side-load obsidian-git plugin (owner-safe)
# Author: deadhedd
set -ex

VAULT_PATH=""
OWNER_USER=""

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
  apt-get install -y --no-install-recommends curl jq unzip
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
  local tmpdeb="$(mktemp --suffix=.deb)"
  echo "Downloading Obsidian: $url"
  curl -fL "$url" -o "$tmpdeb"
  apt-get install -y "$tmpdeb"
  rm -f "$tmpdeb"
}

# ---------- run-as helper (for vault writes) ----------
su_exec() {
  # su_exec <owner> <cmd...>
  local user="$1"; shift
  sudo -u "$user" -- "$@"
}

# ---------- obsidian-git plugin ----------
fetch_latest_obsidian_git_zip_url() {
  curl -fsSL https://api.github.com/repos/Vinzent03/obsidian-git/releases/latest \
  | jq -r '
      .assets[] | select(.name | (endswith(".zip") and . != "Source code (zip)")) | .browser_download_url
    ' | head -n1
}

enable_plugin_in_vault() {
  local vault="$1" plugin_id="$2" owner="$3"
  local cfg="$vault/.obsidian/community-plugins.json"

  su_exec "$owner" mkdir -p "$(dirname "$cfg")"

  if ! su_exec "$owner" test -f "$cfg"; then
    su_exec "$owner" bash -c "echo '[]' > \"$cfg\""
  fi

  # Do the jq edit entirely as the owner (so the final file is theirs)
  su_exec "$owner" bash -c "
    tmpfile=\"\$(mktemp)\"
    jq --arg id '$plugin_id' '( . | index(\$id) ) as \$idx | if \$idx == null then . + [\$id] else . end' \"$cfg\" > \"\$tmpfile\" &&
    mv \"\$tmpfile\" \"$cfg\"
  "
}

install_obsidian_git_plugin() {
  local vault="$1" owner="$2"
  local plugin_id="obsidian-git"
  local plugin_root="$vault/.obsidian/plugins"
  local plugin_dir="$plugin_root/$plugin_id"

  su_exec "$owner" mkdir -p "$plugin_dir"

  local zipurl tmpzip
  zipurl="$(fetch_latest_obsidian_git_zip_url)"
  [ -n "$zipurl" ] && [ "$zipurl" != "null" ] || { echo "Could not find latest obsidian-git release zip." >&2; exit 4; }

  tmpzip="$(su_exec "$owner" mktemp --suffix=.zip | tr -d "\r\n")"
  echo "Downloading obsidian-git: $zipurl"
  su_exec "$owner" bash -c "curl -fL '$zipurl' -o '$tmpzip'"

  # <-- Key change: -j drops internal directories, so manifest.json ends up directly in plugin_dir
  su_exec "$owner" unzip -j -o "$tmpzip" -d "$plugin_dir" >/dev/null
  su_exec "$owner" rm -f "$tmpzip"

  enable_plugin_in_vault "$vault" "$plugin_id" "$owner"

  echo "✅ obsidian-git installed to: $plugin_dir"
  echo "✅ obsidian-git enabled in: $vault/.obsidian/community-plugins.json"
}

# ---------- vault creation ----------
create_vault_if_missing() {
  local vault="$1" owner="$2"
  if [ ! -d "$vault" ]; then
    # create directly owned by the user
    install -d -m 0755 -o "$owner" -g "$owner" "$vault"
  fi
}

# ---------- args ----------
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --vault) VAULT_PATH="${2:-}"; shift 2 ;;
      --owner) OWNER_USER="${2:-}"; shift 2 ;;
      --help|-h)
        cat <<EOF
Usage: sudo $0 --vault /absolute/path/to/Vault --owner USER
Installs Obsidian (.deb) and side-loads/enables the obsidian-git plugin in the given vault.
--owner is required so files are created with the correct ownership.
EOF
        exit 0 ;;
      *) echo "Unknown arg: $1" >&2; exit 9 ;;
    esac
  done

  [ -n "$VAULT_PATH" ] || { echo "Missing required --vault /path/to/Vault" >&2; exit 8; }
  [ -n "$OWNER_USER" ] || { echo "Missing required --owner USER" >&2; exit 8; }
  id "$OWNER_USER" >/dev/null 2>&1 || { echo "User '$OWNER_USER' does not exist" >&2; exit 8; }
}

main() {
  require_root
  parse_args "$@"
  install_prereqs

  # Ensure vault exists and is owned by the target user
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

  # Install & enable obsidian-git as the owner user
  install_obsidian_git_plugin "$VAULT_PATH" "$OWNER_USER"

  echo "All done."
}

main "$@"
