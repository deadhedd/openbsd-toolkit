deploy_ssh_key() {
  local user="$1"      # e.g. “git” or “obsidian”
  local priv_var="${user^^}_SSH_PRIVATE_KEY"
  local pub_var ="${user^^}_SSH_PUBLIC_KEY"
  local sshdir="/home/${user}/.ssh"

  # if we have a private key, write it
  if [ -n "${!priv_var}" ]; then
    mkdir -p "$sshdir"
    chmod 700  "$sshdir"
    printf '%s\n' "${!priv_var}" > "$sshdir/id_ed25519"
    chmod 600  "$sshdir/id_ed25519"
  fi

  # if we have a public key, write it
  if [ -n "${!pub_var}" ]; then
    mkdir -p "$sshdir"
    chmod 700  "$sshdir"
    printf '%s\n' "${!pub_var}" > "$sshdir/id_ed25519.pub"
    chmod 644  "$sshdir/id_ed25519.pub"
  fi

  chown -R "${user}:${user}" "$sshdir"

  # optional: add to agent if you’re running one
  su - "$user" -c "ssh-add '$sshdir/id_ed25519' 2>/dev/null || true"
}

# Deploy keys for both users
deploy_ssh_key "git"
deploy_ssh_key "obsidian"

