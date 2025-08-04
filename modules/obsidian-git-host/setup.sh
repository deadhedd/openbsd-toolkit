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

# -----------------------------------------------------------------------------
# Idempotency helpers (commented out until dry-run/rollback is implemented)
# -----------------------------------------------------------------------------
# DRY_RUN="false"
# ROLLBACK_CMDS=""
# run_cmd() {
#   _cmd="$1"
#   _rollback="$2"
#   if [ "$DRY_RUN" = "true" ]; then
#     printf '[DRY RUN] %s\n' "$_cmd"
#   else
#     eval "$_cmd"
#     ROLLBACK_CMDS="$_rollback\n$ROLLBACK_CMDS"
#   fi
# }
# rollback() {
#   printf '%s' "$ROLLBACK_CMDS" | while IFS= read -r _rb; do
#     [ -n "$_rb" ] && eval "$_rb"
#   done
# }
# trap rollback EXIT

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
# run_cmd "pkg_add -v git" "pkg_delete git"
pkg_add -v git

##############################################################################
# 5) Users & group
##############################################################################
for u in "$OBS_USER" "$GIT_USER"; do
  shell_path=$([ "$u" = "$OBS_USER" ] && echo '/bin/ksh' || echo '/usr/local/bin/git-shell')
  if ! id "$u" >/dev/null 2>&1; then
      # TODO: Idempotency: Rollback handling and dry-run mode
      # run_cmd "useradd -m -s $shell_path $u" "userdel $u"
      useradd -m -s "$shell_path" "$u"
      # TODO: Idempotency: Rollback handling and dry-run mode
      # run_cmd "usermod -p '' $u" "passwd -l $u"
      usermod -p '' "$u"
  fi
done

# TODO: Idempotency: Rollback handling and dry-run mode
# run_cmd "groupadd vault" "groupdel vault"
groupadd vault || true
# TODO: Idempotency: Rollback handling and dry-run mode
# run_cmd "usermod -G vault $OBS_USER" "usermod -G '' $OBS_USER"
usermod -G vault "$OBS_USER"
# TODO: Idempotency: Rollback handling and dry-run mode
# run_cmd "usermod -G vault $GIT_USER" "usermod -G '' $GIT_USER"
usermod -G vault "$GIT_USER"

##############################################################################
# 6) doas config
##############################################################################

# TODO: idempotency: state detection
# TODO: idempotency: rollback handling and dry-run mode
# run_cmd "cat > /etc/doas.conf" "rm -f /etc/doas.conf"
cat > /etc/doas.conf <<EOF
permit persist ${OBS_USER} as root
permit nopass ${GIT_USER} as root cmd git*
permit nopass ${GIT_USER} as ${OBS_USER} cmd git*
EOF
# TODO: Idempotency: Rollback handling and dry-run mode
# run_cmd "chown root:wheel /etc/doas.conf" "chown root:wheel /etc/doas.conf"
chown root:wheel /etc/doas.conf
# TODO: Idempotency: Rollback handling and dry-run mode
# run_cmd "chmod 0440 /etc/doas.conf" "chmod 0644 /etc/doas.conf"
chmod 0440 /etc/doas.conf

##############################################################################
# 7) SSH hardening & per-user SSH dirs
##############################################################################

# 7.1 SSH Service & Config
  if grep -q '^AllowUsers ' /etc/ssh/sshd_config; then
    # TODO: idempotency: Safe editing or replace+template with checksum
    # TODO: idempotency: rollback handling and dry-run mode
    # run_cmd "cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak && sed -i \"/^AllowUsers /c\\AllowUsers ${OBS_USER} ${GIT_USER}\" /etc/ssh/sshd_config" "mv /etc/ssh/sshd_config.bak /etc/ssh/sshd_config"
    sed -i "/^AllowUsers /c\\AllowUsers ${OBS_USER} ${GIT_USER}" /etc/ssh/sshd_config
  else
    # TODO: idempotency: Safe editing or replace+template with checksum
    # TODO: idempotency: rollback handling and dry-run mode
    # run_cmd "echo AllowUsers ${OBS_USER} ${GIT_USER} >> /etc/ssh/sshd_config" "sed -i '/AllowUsers ${OBS_USER} ${GIT_USER}/d' /etc/ssh/sshd_config"
    echo "AllowUsers ${OBS_USER} ${GIT_USER}" >> /etc/ssh/sshd_config
  fi
  # TODO: Idempotency: Rollback handling and dry-run mode
  # run_cmd "rcctl restart sshd" "rcctl restart sshd"
  rcctl restart sshd

# 7.2 .ssh Directories and authorized users
for u in "$OBS_USER" "$GIT_USER"; do
  HOME_DIR="/home/$u"
  SSH_DIR="$HOME_DIR/.ssh"
    # TODO: idempotency: state detection
    # TODO: idempotency: rollback handling and dry-run mode
    # run_cmd "mkdir -p $SSH_DIR" "rmdir $SSH_DIR"
    mkdir -p "$SSH_DIR"
    # TODO: Idempotency: Rollback handling and dry-run mode
    # run_cmd "chmod 700 $SSH_DIR" "chmod 755 $SSH_DIR"
    chmod 700 "$SSH_DIR"
    # TODO: idempotency: state detection
    # TODO: idempotency: rollback handling and dry-run mode
    # run_cmd "touch $SSH_DIR/authorized_keys" "rm -f $SSH_DIR/authorized_keys"
    touch "$SSH_DIR/authorized_keys"
    # TODO: Idempotency: Rollback handling and dry-run mode
    # run_cmd "chmod 600 $SSH_DIR/authorized_keys" "chmod 644 $SSH_DIR/authorized_keys"
    chmod 600 "$SSH_DIR/authorized_keys"
    # TODO: Idempotency: Rollback handling and dry-run mode
    # run_cmd "chown -R $u:$u $SSH_DIR" "chown -R root:wheel $SSH_DIR"
    chown -R "$u:$u" "$SSH_DIR"
done

# 7.3 Known Hosts (OBS_USER only)
# TODO: idempotency: state detection
# TODO: idempotency: Safe editing or replace+template with checksum
# TODO: idempotency: rollback handling and dry-run mode
# run_cmd "ssh-keyscan -H $GIT_SERVER >> /home/${OBS_USER}/.ssh/known_hosts" "sed -i '/$GIT_SERVER/d' /home/${OBS_USER}/.ssh/known_hosts"
ssh-keyscan -H "$GIT_SERVER" >> "/home/${OBS_USER}/.ssh/known_hosts"
# TODO: idempotency rollback handling and dry-run mode
# run_cmd "chmod 644 /home/${OBS_USER}/.ssh/known_hosts" "chmod 600 /home/${OBS_USER}/.ssh/known_hosts"
chmod 644 "/home/${OBS_USER}/.ssh/known_hosts"
# TODO: idempotency rollback handling and dry-run mode
# run_cmd "chown ${OBS_USER}:${OBS_USER} /home/${OBS_USER}/.ssh/known_hosts" "chown root:wheel /home/${OBS_USER}/.ssh/known_hosts"
chown "${OBS_USER}:${OBS_USER}" "/home/${OBS_USER}/.ssh/known_hosts"

##############################################################################
# 8) Repo paths & bare init
##############################################################################

VAULT_DIR="/home/${GIT_USER}/vaults"
BARE_REPO="${VAULT_DIR}/${VAULT}.git"
# TODO: idempotency: state detection
# TODO: idempotency: rollback handling and dry-run mode
# run_cmd "mkdir -p $VAULT_DIR" "rmdir $VAULT_DIR"
mkdir -p "$VAULT_DIR"
# TODO: idempotency: state detection
# TODO: idempotency: rollback handling and dry-run mode
# run_cmd "chown ${GIT_USER}:${GIT_USER} $VAULT_DIR" "chown root:wheel $VAULT_DIR"
chown "${GIT_USER}:${GIT_USER}" "$VAULT_DIR"

# TODO: idempotency: state detection
# TODO: idempotency: rollback handling and dry-run mode
# run_cmd "git init --bare $BARE_REPO" "rm -rf $BARE_REPO"
git init --bare "$BARE_REPO"
# TODO: idempotency: state detection
# TODO: idempotency: rollback handling and dry-run mode
# run_cmd "chown -R ${GIT_USER}:${GIT_USER} $BARE_REPO" "chown -R root:wheel $BARE_REPO"
chown -R "${GIT_USER}:${GIT_USER}" "$BARE_REPO"

##############################################################################
# 9) Git configs (safe.directory, sharedRepository)
##############################################################################

for u in "$GIT_USER" "$OBS_USER"; do
  cfg="/home/$u/.gitconfig"
    # TODO: idempotency: state detection
    # TODO: idempotency: rollback handling and dry-run mode
    # run_cmd "touch $cfg" "rm -f $cfg"
    touch "$cfg"
  if [ "$u" = "$GIT_USER" ]; then
      # TODO: idempotency: Safe editing or replace+template with checksum
      # TODO: idempotency: rollback handling and dry-run mode
      # run_cmd "git config --file $cfg --add safe.directory $BARE_REPO" "git config --file $cfg --unset-all safe.directory $BARE_REPO"
      git config --file "$cfg" --add safe.directory "$BARE_REPO"
      # TODO: idempotency: Safe editing or replace+template with checksum
      # TODO: idempotency: rollback handling and dry-run mode
      # run_cmd "git config --file $cfg --add safe.directory /home/${OBS_USER}/vaults/${VAULT}" "git config --file $cfg --unset-all safe.directory /home/${OBS_USER}/vaults/${VAULT}"
      git config --file "$cfg" --add safe.directory "/home/${OBS_USER}/vaults/${VAULT}"
  else
      # TODO: idempotency: Safe editing or replace+template with checksum
      # TODO: idempotency: rollback handling and dry-run mode
      # run_cmd "git config --file $cfg --add safe.directory /home/${OBS_USER}/vaults/${VAULT}" "git config --file $cfg --unset-all safe.directory /home/${OBS_USER}/vaults/${VAULT}"
      git config --file "$cfg" --add safe.directory "/home/${OBS_USER}/vaults/${VAULT}"
  fi
    # TODO: Idempotency: Rollback handling and dry-run mode
    # run_cmd "chown $u:$u $cfg" "chown root:wheel $cfg"
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
# run_cmd "cat > $HOOK" "rm -f $HOOK"
cat > "$HOOK" <<EOF
#!/bin/sh
SHA=\$(cat "$BARE_REPO/refs/heads/master")
su - $OBS_USER -c "/usr/local/bin/git --git-dir=$BARE_REPO --work-tree=$WORK_DIR checkout -f \$SHA"
exit 0
EOF

# TODO: Idempotency: Rollback handling and dry-run mode
# run_cmd "chown ${GIT_USER}:${GIT_USER} $HOOK" "chown root:wheel $HOOK"
chown "${GIT_USER}:${GIT_USER}" "$HOOK"
# TODO: Idempotency: Rollback handling and dry-run mode
# run_cmd "chmod +x $HOOK" "chmod -x $HOOK"
chmod +x "$HOOK"

##############################################################################
# 11) Working copy clone & initial commit
##############################################################################

# TODO: Idempotency: State detection
# TODO: Idempotency: Rollback handling and dry-run mode
# run_cmd "mkdir -p $(dirname $WORK_DIR)" "rmdir $(dirname $WORK_DIR)"
mkdir -p "$(dirname "$WORK_DIR")"
# TODO: Idempotency: State detection
# TODO: Idempotency: Rollback handling and dry-run mode
# run_cmd "git -c safe.directory=$BARE_REPO clone $BARE_REPO $WORK_DIR" "rm -rf $WORK_DIR"
git -c safe.directory="$BARE_REPO" clone "$BARE_REPO" "$WORK_DIR"
# TODO: Idempotency: rollback handling and dry-run mode
# run_cmd "chown -R ${OBS_USER}:${OBS_USER} $WORK_DIR" "chown -R root:wheel $WORK_DIR"
chown -R "${OBS_USER}:${OBS_USER}" "$WORK_DIR"

# TODO: Idempotency: rollback handling and dry-run mode
  # run_cmd "git -C $WORK_DIR -c safe.directory=$WORK_DIR -c user.name='Obsidian User' -c user.email='obsidian@example.com' commit --allow-empty -m 'initial commit'" "git -C $WORK_DIR reset --hard HEAD~1"
  git -C "$WORK_DIR" \
      -c safe.directory="$WORK_DIR" \
      -c user.name='Obsidian User' \
      -c user.email='obsidian@example.com' \
      commit --allow-empty -m 'initial commit'

##############################################################################
# 12) Final perms on bare repo
##############################################################################

# TODO: Idempotency: rollback handling and dry-run mode
# run_cmd "git --git-dir=$BARE_REPO config core.sharedRepository group" "git --git-dir=$BARE_REPO config --unset core.sharedRepository"
git --git-dir="$BARE_REPO" config core.sharedRepository group
# TODO: Idempotency: rollback handling and dry-run mode
# run_cmd "chown -R ${GIT_USER}:vault $BARE_REPO" "chown -R root:wheel $BARE_REPO"
chown -R "${GIT_USER}:vault" "$BARE_REPO"
# TODO: Idempotency: rollback handling and dry-run mode
# run_cmd "chmod -R g+rwX $BARE_REPO" "chmod -R go-rwx $BARE_REPO"
chmod -R g+rwX "$BARE_REPO"
# TODO: Idempotency: rollback handling and dry-run mode
# run_cmd "find $BARE_REPO -type d -exec chmod g+s {} +" "find $BARE_REPO -type d -exec chmod g-s {} +"
find "$BARE_REPO" -type d -exec chmod g+s {} +

##############################################################################
# 13) History settings (.profile)
##############################################################################

for u in "$OBS_USER" "$GIT_USER"; do
  PROFILE="/home/$u/.profile"
      # TODO: Idempotency: State detection
      # TODO: Idempotency: Safe editing or replace+template with checksum
      # TODO: Idempotency: Rollback handling and dry-run mode
      # run_cmd "cat >> $PROFILE" "cp ${PROFILE}.bak $PROFILE"
      cat <<EOF >> "$PROFILE"
export HISTFILE=/home/$u/.ksh_history
export HISTSIZE=5000
export HISTCONTROL=ignoredups
EOF
    # TODO: Idempotency: Rollback handling and dry-run mode
    # run_cmd "chown $u:$u $PROFILE" "chown root:wheel $PROFILE"
    chown "$u:$u" "$PROFILE"
done

echo "obsidian-git-host: Vault setup complete!"
