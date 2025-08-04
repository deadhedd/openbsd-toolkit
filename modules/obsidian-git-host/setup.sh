#!/bin/sh
# modules/obsidian-git-host/setup.sh — Git-backed Obsidian vault setup
# Author: deadhedd
# Version: 1.0.0
# Updated: 2025-08-02
#
# Usage: sh setup.sh [--debug[=FILE]] [-h]
#
# Description:
#   Sets up Git/Obsidian users and group, hardens SSH, writes doas rules,
#   initializes the bare repo and working copy, installs the post-receive hook,
#   and fixes perms (incl. setgid dirs) for group collaboration.
#
# Deployment considerations:
#   Requires these vars (exported via config/load-secrets.sh):
#     • OBS_USER, GIT_USER, VAULT, GIT_SERVER
#   Assumes pkg_add git is available and run as root on OpenBSD.
#
# Security note:
#   Enabling the --debug flag will log all executed commands *and their expanded
#   values* (via `set -vx`), including any exported secrets or credentials.
#   Use caution when sharing or retaining debug logs.
#
# See also:
#   - modules/obsidian-git-host/test.sh
#   - logs/logging.sh
#   - config/load-secrets.sh

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
  Usage: sh $(basename "$0") [options]

  Description:
    Set up Git user, vault repository, and post-receive hook

  Options:
    -h, --help        Show this help message and exit
    -d, --debug       Enable debug/xtrace and write a log file
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
# 3) Secrets & required vars
##############################################################################

. "$PROJECT_ROOT/config/load-secrets.sh"
: "${OBS_USER:?OBS_USER must be set in secrets}"
: "${GIT_USER:?GIT_USER must be set in secrets}"
: "${VAULT:?VAULT must be set in secrets}"
: "${GIT_SERVER:?GIT_SERVER must be set in secrets}"

##############################################################################
# 4) Packages
##############################################################################

# TODO: Idempotency: Rollback handling and dry-run mode
pkg_add -v git

##############################################################################
# 5) Users & group
##############################################################################
for u in "$OBS_USER" "$GIT_USER"; do
  shell_path=$([ "$u" = "$OBS_USER" ] && echo '/bin/ksh' || echo '/usr/local/bin/git-shell')
  if ! id "$u" >/dev/null 2>&1; then
      # TODO: Idempotency: Rollback handling and dry-run mode
      useradd -m -s "$shell_path" "$u"
      # TODO: Idempotency: Rollback handling and dry-run mode
      usermod -p '' "$u"
  fi
done

# TODO: Idempotency: Rollback handling and dry-run mode
groupadd vault || true
# TODO: Idempotency: Rollback handling and dry-run mode
usermod -G vault "$OBS_USER"
# TODO: Idempotency: Rollback handling and dry-run mode
usermod -G vault "$GIT_USER"

##############################################################################
# 6) doas config
##############################################################################

# TODO: idempotency: state detection
# TODO: idempotency: rollback handling and dry-run mode
cat > /etc/doas.conf <<EOF
permit persist ${OBS_USER} as root
permit nopass ${GIT_USER} as root cmd git*
permit nopass ${GIT_USER} as ${OBS_USER} cmd git*
EOF
# TODO: Idempotency: Rollback handling and dry-run mode
chown root:wheel /etc/doas.conf
# TODO: Idempotency: Rollback handling and dry-run mode
chmod 0440 /etc/doas.conf

##############################################################################
# 7) SSH hardening & per-user SSH dirs
##############################################################################

# 7.1 SSH Service & Config
  if grep -q '^AllowUsers ' /etc/ssh/sshd_config; then
    # TODO: idempotency: Safe editing or replace+template with checksum
    # TODO: idempotency: rollback handling and dry-run mode
    sed -i "/^AllowUsers /c\\AllowUsers ${OBS_USER} ${GIT_USER}" /etc/ssh/sshd_config
  else
    # TODO: idempotency: Safe editing or replace+template with checksum
    # TODO: idempotency: rollback handling and dry-run mode
    echo "AllowUsers ${OBS_USER} ${GIT_USER}" >> /etc/ssh/sshd_config
  fi
  # TODO: Idempotency: Rollback handling and dry-run mode
  rcctl restart sshd

# 7.2 .ssh Directories and authorized users
for u in "$OBS_USER" "$GIT_USER"; do
  HOME_DIR="/home/$u"
  SSH_DIR="$HOME_DIR/.ssh"
    # TODO: idempotency: state detection
    # TODO: idempotency: rollback handling and dry-run mode
    mkdir -p "$SSH_DIR"
    # TODO: Idempotency: Rollback handling and dry-run mode
    chmod 700 "$SSH_DIR"
    # TODO: idempotency: state detection
    # TODO: idempotency: rollback handling and dry-run mode
    touch "$SSH_DIR/authorized_keys"
    # TODO: Idempotency: Rollback handling and dry-run mode
    chmod 600 "$SSH_DIR/authorized_keys"
    # TODO: Idempotency: Rollback handling and dry-run mode
    chown -R "$u:$u" "$SSH_DIR"
done

# 7.3 Known Hosts (OBS_USER only)
# TODO: idempotency: state detection
# TODO: idempotency: Safe editing or replace+template with checksum
# TODO: idempotency: rollback handling and dry-run mode
ssh-keyscan -H "$GIT_SERVER" >> "/home/${OBS_USER}/.ssh/known_hosts"
# TODO: idempotency rollback handling and dry-run mode
chmod 644 "/home/${OBS_USER}/.ssh/known_hosts"
# TODO: idempotency rollback handling and dry-run mode
chown "${OBS_USER}:${OBS_USER}" "/home/${OBS_USER}/.ssh/known_hosts"

##############################################################################
# 8) Repo paths & bare init
##############################################################################

VAULT_DIR="/home/${GIT_USER}/vaults"
BARE_REPO="${VAULT_DIR}/${VAULT}.git"
# TODO: idempotency: state detection
# TODO: idempotency: rollback handling and dry-run mode
mkdir -p "$VAULT_DIR"
# TODO: idempotency: state detection
# TODO: idempotency: rollback handling and dry-run mode
chown "${GIT_USER}:${GIT_USER}" "$VAULT_DIR"

# TODO: idempotency: state detection
# TODO: idempotency: rollback handling and dry-run mode
git init --bare "$BARE_REPO"
# TODO: idempotency: state detection
# TODO: idempotency: rollback handling and dry-run mode
chown -R "${GIT_USER}:${GIT_USER}" "$BARE_REPO"

##############################################################################
# 9) Git configs (safe.directory, sharedRepository)
##############################################################################

for u in "$GIT_USER" "$OBS_USER"; do
  cfg="/home/$u/.gitconfig"
    # TODO: idempotency: state detection
    # TODO: idempotency: rollback handling and dry-run mode
    touch "$cfg"
  if [ "$u" = "$GIT_USER" ]; then
      # TODO: idempotency: Safe editing or replace+template with checksum
      # TODO: idempotency: rollback handling and dry-run mode
      git config --file "$cfg" --add safe.directory "$BARE_REPO"
      # TODO: idempotency: Safe editing or replace+template with checksum
      # TODO: idempotency: rollback handling and dry-run mode
      git config --file "$cfg" --add safe.directory "/home/${OBS_USER}/vaults/${VAULT}"
  else
      # TODO: idempotency: Safe editing or replace+template with checksum
      # TODO: idempotency: rollback handling and dry-run mode
      git config --file "$cfg" --add safe.directory "/home/${OBS_USER}/vaults/${VAULT}"
  fi
    # TODO: Idempotency: Rollback handling and dry-run mode
    chown "$u:$u" "$cfg"
done

##############################################################################
# 10) Post-receive hook
##############################################################################

WORK_DIR="/home/${OBS_USER}/vaults/${VAULT}"
HOOK="$BARE_REPO/hooks/post-receive"

# TODO: Idempotency: state detection
# TODO: Idempotency: Safe editing or replace+template with checksum
# TODO: Idempotency: Rollback handling and dry-run mode
cat > "$HOOK" <<EOF
#!/bin/sh
SHA=\$(cat "$BARE_REPO/refs/heads/master")
su - $OBS_USER -c "/usr/local/bin/git --git-dir=$BARE_REPO --work-tree=$WORK_DIR checkout -f \$SHA"
exit 0
EOF

# TODO: Idempotency: Rollback handling and dry-run mode
chown "${GIT_USER}:${GIT_USER}" "$HOOK"
# TODO: Idempotency: Rollback handling and dry-run mode
chmod +x "$HOOK"

##############################################################################
# 11) Working copy clone & initial commit
##############################################################################

# TODO: Idempotency: State detection
# TODO: Idempotency: Rollback handling and dry-run mode
mkdir -p "$(dirname "$WORK_DIR")"
# TODO: Idempotency: State detection
# TODO: Idempotency: Rollback handling and dry-run mode
git -c safe.directory="$BARE_REPO" clone "$BARE_REPO" "$WORK_DIR"
# TODO: Idempotency: rollback handling and dry-run mode
chown -R "${OBS_USER}:${OBS_USER}" "$WORK_DIR"

# TODO: Idempotency: rollback handling and dry-run mode
  git -C "$WORK_DIR" \
      -c safe.directory="$WORK_DIR" \
      -c user.name='Obsidian User' \
      -c user.email='obsidian@example.com' \
      commit --allow-empty -m 'initial commit'

##############################################################################
# 12) Final perms on bare repo
##############################################################################

# TODO: Idempotency: rollback handling and dry-run mode
git --git-dir="$BARE_REPO" config core.sharedRepository group
# TODO: Idempotency: rollback handling and dry-run mode
chown -R "${GIT_USER}:vault" "$BARE_REPO"
# TODO: Idempotency: rollback handling and dry-run mode
chmod -R g+rwX "$BARE_REPO"
# TODO: Idempotency: rollback handling and dry-run mode
find "$BARE_REPO" -type d -exec chmod g+s {} +

##############################################################################
# 13) History settings (.profile)
##############################################################################

for u in "$OBS_USER" "$GIT_USER"; do
  PROFILE="/home/$u/.profile"
      # TODO: Idempotency: State detection
      # TODO: Idempotency: Safe editing or replace+template with checksum
      # TODO: Idempotency: Rollback handling and dry-run mode
      cat <<EOF >> "$PROFILE"
export HISTFILE=/home/$u/.ksh_history
export HISTSIZE=5000
export HISTCONTROL=ignoredups
EOF
    # TODO: Idempotency: Rollback handling and dry-run mode
    chown "$u:$u" "$PROFILE"
done

echo "obsidian-git-host: Vault setup complete!"
