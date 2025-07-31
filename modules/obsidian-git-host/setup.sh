#!/bin/sh #
# modules/obsidian-git-host/setup.sh — Git-backed Obsidian vault setup
# Author: deadhedd
# Version: 1.0.0
# Updated: 2025-07-28
#
# Usage: ./setup.sh [--debug[=FILE]] [-h]
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
  cat <<-EOF
  Usage: $(basename "$0") [options]

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
parse_logging_flags "$@"
eval "set -- $REMAINING_ARGS"

module_name="$(basename "$SCRIPT_DIR")"
if [ "$DEBUG_MODE" -eq 1 ]; then
  set -vx  # enable xtrace
  init_logging "setup-$module_name"
fi

##############################################################################
# 3) Secrets & required vars
##############################################################################

. "$PROJECT_ROOT/config/load_secrets.sh"
: "${OBS_USER:?OBS_USER must be set in secrets}"
: "${GIT_USER:?GIT_USER must be set in secrets}"
: "${VAULT:?VAULT must be set in secrets}"
: "${GIT_SERVER:?GIT_SERVER must be set in secrets}"

##############################################################################
# 4) Packages
##############################################################################

pkg_add -v git

##############################################################################
# 5) Users & group
##############################################################################
for u in "$OBS_USER" "$GIT_USER"; do
  shell_path=$([ "$u" = "$OBS_USER" ] && echo '/bin/ksh' || echo '/usr/local/bin/git-shell')
  if ! id "$u" >/dev/null 2>&1; then
    useradd -m -s "$shell_path" "$u"
    usermod -p '' "$u"
  fi
done

groupadd vault || true
usermod -G vault "$OBS_USER"
usermod -G vault "$GIT_USER"

##############################################################################
# 6) doas config
##############################################################################

cat > /etc/doas.conf <<-EOF
permit persist ${OBS_USER} as root
permit nopass ${GIT_USER} as root cmd git*
permit nopass ${GIT_USER} as ${OBS_USER} cmd git*
EOF
chown root:wheel /etc/doas.conf
chmod 0440 /etc/doas.conf

##############################################################################
# 7) SSH hardening & per-user SSH dirs
##############################################################################

# 7.1 SSH Service & Config
if grep -q '^AllowUsers ' /etc/ssh/sshd_config; then
  sed -i "/^AllowUsers /c\\AllowUsers ${OBS_USER} ${GIT_USER}" /etc/ssh/sshd_config
else
  echo "AllowUsers ${OBS_USER} ${GIT_USER}" >> /etc/ssh/sshd_config
fi
rcctl restart sshd

# 7.2 .ssh Directories and authorized users
for u in "$OBS_USER" "$GIT_USER"; do
  HOME_DIR="/home/$u"
  SSH_DIR="$HOME_DIR/.ssh"
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"
  touch "$SSH_DIR/authorized_keys"
  chmod 600 "$SSH_DIR/authorized_keys"
  chown -R "$u:$u" "$SSH_DIR"
done

# 7.3 Known Hosts (OBS_USER only)
ssh-keyscan -H "$GIT_SERVER" >> "/home/${OBS_USER}/.ssh/known_hosts"
chmod 644 "/home/${OBS_USER}/.ssh/known_hosts"
chown "${OBS_USER}:${OBS_USER}" "/home/${OBS_USER}/.ssh/known_hosts"

##############################################################################
# 8) Repo paths & bare init
##############################################################################

VAULT_DIR="/home/${GIT_USER}/vaults"
BARE_REPO="${VAULT_DIR}/${VAULT}.git"
mkdir -p "$VAULT_DIR"
chown "${GIT_USER}:${GIT_USER}" "$VAULT_DIR"

git init --bare "$BARE_REPO"
chown -R "${GIT_USER}:${GIT_USER}" "$BARE_REPO"

##############################################################################
# 9) Git configs (safe.directory, sharedRepository)
##############################################################################

for u in "$GIT_USER" "$OBS_USER"; do
  cfg="/home/$u/.gitconfig"
  touch "$cfg"
  if [ "$u" = "$GIT_USER" ]; then
    git config --file "$cfg" --add safe.directory "$BARE_REPO"
    git config --file "$cfg" --add safe.directory "/home/${OBS_USER}/vaults/${VAULT}"
  else
    git config --file "$cfg" --add safe.directory "/home/${OBS_USER}/vaults/${VAULT}"
  fi
  chown "$u:$u" "$cfg"
done

##############################################################################
# 10) Post-receive hook
##############################################################################

WORK_DIR="/home/${OBS_USER}/vaults/${VAULT}"
HOOK="$BARE_REPO/hooks/post-receive"

cat > "$HOOK" <<-EOF
#!/bin/sh
SHA=\$(cat "$BARE_REPO/refs/heads/master")
su - $OBS_USER -c "/usr/local/bin/git --git-dir=$BARE_REPO --work-tree=$WORK_DIR checkout -f \$SHA"
exit 0
EOF

chown "${GIT_USER}:${GIT_USER}" "$HOOK"
chmod +x "$HOOK"

##############################################################################
# 11) Working copy clone & initial commit
##############################################################################

mkdir -p "$(dirname "$WORK_DIR")"
git -c safe.directory="$BARE_REPO" clone "$BARE_REPO" "$WORK_DIR"
chown -R "${OBS_USER}:${OBS_USER}" "$WORK_DIR"

git -C "$WORK_DIR" \
    -c safe.directory="$WORK_DIR" \
    -c user.name='Obsidian User' \
    -c user.email='obsidian@example.com' \
    commit --allow-empty -m 'initial commit'

##############################################################################
# 12) Final perms on bare repo
##############################################################################

git --git-dir="$BARE_REPO" config core.sharedRepository group
chown -R "${GIT_USER}:vault" "$BARE_REPO"
chmod -R g+rwX "$BARE_REPO"
find "$BARE_REPO" -type d -exec chmod g+s {} +

##############################################################################
# 13) History settings (.profile)
##############################################################################

for u in "$OBS_USER" "$GIT_USER"; do
  PROFILE="/home/$u/.profile"
  cat <<-EOF >> "$PROFILE"
export HISTFILE=/home/$u/.ksh_history
export HISTSIZE=5000
export HISTCONTROL=ignoredups
EOF
  chown "$u:$u" "$PROFILE"
done

echo "obsidian-git-host: Vault setup complete!"
