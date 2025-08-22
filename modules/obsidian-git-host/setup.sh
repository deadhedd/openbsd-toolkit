#!/bin/sh
# modules/obsidian-git-host/setup.sh — Git-backed Obsidian vault setup
# Author: deadhedd
# Version: 1.0.2
# Updated: 2025-08-22
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
#     • OBS_USER, GIT_USER, VAULT
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

# Merge unique tokens in a directive line without clobbering existing values.
safe_replace_line() {
  _file="$1"
  _directive="$2"
  shift 2
  _values="$*"
  if [ -f "$_file" ] && grep -q "^${_directive} " "$_file"; then
    _existing="$(grep "^${_directive} " "$_file" | head -n1 | cut -d' ' -f2-)"
    _combined="$(printf '%s\n%s\n' "$_existing" "$_values" | tr ' ' '\n' | sort -u | tr '\n' ' ')"
    _combined="$(printf '%s' "$_combined" | sed 's/[[:space:]]*$//')"
    sed -i "/^${_directive} /c\\${_directive} ${_combined}" "$_file"
  else
    echo "${_directive} ${_values}" >> "$_file"
  fi
}

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
# safe_append_line() {
#   _file="$1"
#   _line="$2"
#   grep -Fqx "$_line" "$_file" 2>/dev/null && return 0
#   _tmp="$(mktemp)"
#   [ -f "$_file" ] && cp "$_file" "$_tmp"
#   printf '%s\n' "$_line" >> "$_tmp"
#   mv "$_tmp" "$_file"
# }
# safe_replace_line() {
#   _file="$1"
#   _pattern="$2"
#   _replacement="$3"
#   _tmp="$(mktemp)"
#   sed "s|$_pattern|$_replacement|" "$_file" > "$_tmp"
#   cmp -s "$_tmp" "$_file" || mv "$_tmp" "$_file"
#   rm -f "$_tmp"
# }
# safe_write() {
#   _file="$1"
#   _tmp="$(mktemp)"
#   cat > "$_tmp"
#   if ! cmp -s "$_tmp" "$_file" 2>/dev/null; then
#     mv "$_tmp" "$_file"
#   else
#     rm -f "$_tmp"
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

. "$PROJECT_ROOT/config/load-secrets.sh" "Base System"
. "$PROJECT_ROOT/config/load-secrets.sh" "Obsidian Git Host"
: "${ADMIN_USER:?ADMIN_USER must be set in secrets}"
: "${OBS_USER:?OBS_USER must be set in secrets}"
: "${GIT_USER:?GIT_USER must be set in secrets}"
: "${VAULT:?VAULT must be set in secrets}"
: "${GIT_SERVER:?GIT_SERVER must be set in secrets}"

ADMIN_PUB_KEY_PATH="$PROJECT_ROOT/config/$ADMIN_SSH_PUBLIC_KEY_FILE"
if [ -f "$ADMIN_PUB_KEY_PATH" ]; then
  ADMIN_PUB_KEY="$(cat "$ADMIN_PUB_KEY_PATH")"
else
  echo "WARNING: missing admin SSH public key file $ADMIN_PUB_KEY_PATH" >&2
  ADMIN_PUB_KEY=""
fi

##############################################################################
# 4) Packages
##############################################################################

# Idempotency: rollback handling and dry-run mode example
# run_cmd "pkg_add -v git" "pkg_delete git"
pkg_add -v git

##############################################################################
# 5) Users & group
##############################################################################
for u in "$OBS_USER" "$GIT_USER"; do
  shell_path=$([ "$u" = "$OBS_USER" ] && echo '/bin/ksh' || echo '/usr/local/bin/git-shell')
  if ! id "$u" >/dev/null 2>&1; then
      # Idempotency: rollback handling and dry-run mode example
      # run_cmd "useradd -m -s $shell_path $u" "userdel $u"
      useradd -m -s "$shell_path" "$u"
      # Idempotency: rollback handling and dry-run mode example
      # run_cmd "usermod -p '' $u" "passwd -l $u"
      usermod -p '' "$u"
  fi
done

# Idempotency: rollback handling and dry-run mode example
# run_cmd "groupadd vault" "groupdel vault"
groupadd vault || true
# Idempotency: rollback handling and dry-run mode example
# run_cmd "usermod -G vault $OBS_USER" "usermod -G '' $OBS_USER"
usermod -G vault "$OBS_USER"
# Idempotency: rollback handling and dry-run mode example
# run_cmd "usermod -G vault $GIT_USER" "usermod -G '' $GIT_USER"
usermod -G vault "$GIT_USER"

##############################################################################
# 6) doas config
##############################################################################

DOAS_CONF="/etc/doas.conf"
touch "$DOAS_CONF"

# Append module-specific rules only if they are missing
if ! grep -Fqx "permit persist ${OBS_USER} as root" "$DOAS_CONF"; then
  echo "permit persist ${OBS_USER} as root" >> "$DOAS_CONF"
fi
if ! grep -Fqx "permit nopass ${GIT_USER} as root cmd git*" "$DOAS_CONF"; then
  echo "permit nopass ${GIT_USER} as root cmd git*" >> "$DOAS_CONF"
fi
if ! grep -Fqx "permit nopass ${GIT_USER} as ${OBS_USER} cmd git*" "$DOAS_CONF"; then
  echo "permit nopass ${GIT_USER} as ${OBS_USER} cmd git*" >> "$DOAS_CONF"
fi
# Idempotency: rollback handling and dry-run mode example
# run_cmd "chown root:wheel /etc/doas.conf" "chown root:wheel /etc/doas.conf"
chown root:wheel /etc/doas.conf
# Idempotency: rollback handling and dry-run mode example
# run_cmd "chmod 0440 /etc/doas.conf" "chmod 0644 /etc/doas.conf"
chmod 0440 /etc/doas.conf

##############################################################################
# 7) SSH hardening & per-user SSH dirs
##############################################################################

# 7.1 SSH Service & Config
safe_replace_line /etc/ssh/sshd_config "AllowUsers" "${OBS_USER}" "${GIT_USER}" "${ADMIN_USER}"
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

# Idempotency: rollback handling and dry-run mode example
# run_cmd "mkdir -p $VAULT_DIR" "rmdir $VAULT_DIR"

# Idempotency: state detection example
# [ -d "$VAULT_DIR" ] || mkdir -p "$VAULT_DIR"
mkdir -p "$VAULT_DIR"

# Idempotency: rollback handling and dry-run mode example
# run_cmd "chown ${GIT_USER}:${GIT_USER} $VAULT_DIR" "chown root:wheel $VAULT_DIR"

# Idempotency: state detection example
# [ "$(stat -f %Su \"$VAULT_DIR\" 2>/dev/null)" = "$GIT_USER" ] || chown "${GIT_USER}:${GIT_USER}" "$VAULT_DIR"
chown "${GIT_USER}:${GIT_USER}" "$VAULT_DIR"

# Idempotency: rollback handling and dry-run mode example
# run_cmd "git init --bare $BARE_REPO" "rm -rf $BARE_REPO"

# Idempotency: state detection example
# [ -d "$BARE_REPO" ] || git init --bare "$BARE_REPO"
git init --bare "$BARE_REPO"

# Idempotency: rollback handling and dry-run mode example
# run_cmd "chown -R ${GIT_USER}:${GIT_USER} $BARE_REPO" "chown -R root:wheel $BARE_REPO"

# Idempotency: state detection example
# [ "$(stat -f %Su \"$BARE_REPO\" 2>/dev/null)" = "$GIT_USER" ] || chown -R "${GIT_USER}:${GIT_USER}" "$BARE_REPO"
chown -R "${GIT_USER}:${GIT_USER}" "$BARE_REPO"

##############################################################################
# 9) Git configs (safe.directory, sharedRepository)
##############################################################################

for u in "$GIT_USER" "$OBS_USER"; do
  cfg="/home/$u/.gitconfig"
    
    # Idempotency: rollback handling and dry-run mode example
    # run_cmd "touch $cfg" "rm -f $cfg"
    
    # Idempotency: state detection example
    # [ -f "$cfg" ] || touch "$cfg"
    touch "$cfg"
  if [ "$u" = "$GIT_USER" ]; then
      
      # Idempotency: rollback handling and dry-run mode example
      # run_cmd "git config --file $cfg --add safe.directory $BARE_REPO" "git config --file $cfg --unset-all safe.directory $BARE_REPO"
      
      # Idempotency: safe editing example
      # git config --file "$cfg" --get-all safe.directory | grep -qx "$BARE_REPO" || git config --file "$cfg" --add safe.directory "$BARE_REPO"

# Idempotency: replace+template with checksum example
# tmp_cfg="$(mktemp)"
# cat > "$tmp_cfg" <<EOF
# [safe]
#     directory = $BARE_REPO
#     directory = /home/${OBS_USER}/vaults/${VAULT}
# EOF
# old_sum="$(sha256 -q "$cfg" 2>/dev/null || true)"
# new_sum="$(sha256 -q "$tmp_cfg")"
# [ "$old_sum" = "$new_sum" ] || cp "$tmp_cfg" "$cfg"
# rm -f "$tmp_cfg"
      git config --file "$cfg" --add safe.directory "$BARE_REPO"
      
      # Idempotency: rollback handling and dry-run mode example
      # run_cmd "git config --file $cfg --add safe.directory /home/${OBS_USER}/vaults/${VAULT}" "git config --file $cfg --unset-all safe.directory /home/${OBS_USER}/vaults/${VAULT}"
      
      # Idempotency: safe editing example
      # git config --file "$cfg" --get-all safe.directory | grep -qx "/home/${OBS_USER}/vaults/${VAULT}" || git config --file "$cfg" --add safe.directory "/home/${OBS_USER}/vaults/${VAULT}"
      
      # Idempotency: replace+template with checksum example
      # (checksum template block above handles both safe.directory entries)
      git config --file "$cfg" --add safe.directory "/home/${OBS_USER}/vaults/${VAULT}"
  else
      
      # Idempotency: rollback handling and dry-run mode example
      # run_cmd "git config --file $cfg --add safe.directory /home/${OBS_USER}/vaults/${VAULT}" "git config --file $cfg --unset-all safe.directory /home/${OBS_USER}/vaults/${VAULT}"
      
      # Idempotency: safe editing example
      # git config --file "$cfg" --get-all safe.directory | grep -qx "/home/${OBS_USER}/vaults/${VAULT}" || git config --file "$cfg" --add safe.directory "/home/${OBS_USER}/vaults/${VAULT}"

# Idempotency: replace+template with checksum example
# tmp_cfg="$(mktemp)"
# cat > "$tmp_cfg" <<EOF
# [safe]
#     directory = /home/${OBS_USER}/vaults/${VAULT}
# EOF
# old_sum="$(sha256 -q "$cfg" 2>/dev/null || true)"
# new_sum="$(sha256 -q "$tmp_cfg")"
# [ "$old_sum" = "$new_sum" ] || cp "$tmp_cfg" "$cfg"
# rm -f "$tmp_cfg"
      
      # Idempotency: replace+template with checksum example
      # (checksum template block above handles safe.directory entry idempotently)
      git config --file "$cfg" --add safe.directory "/home/${OBS_USER}/vaults/${VAULT}"
  fi
    # Idempotency: rollback handling and dry-run mode example
    # run_cmd "chown $u:$u $cfg" "chown root:wheel $cfg"
    chown "$u:$u" "$cfg"
done

##############################################################################
# 10) Post-receive hook
##############################################################################

WORK_DIR="/home/${OBS_USER}/vaults/${VAULT}"
HOOK="$BARE_REPO/hooks/post-receive"

# TODO: Idempotency: state detection

# Idempotency: rollback handling and dry-run mode example
# run_cmd "cat > $HOOK" "rm -f $HOOK"

# Idempotency: safe editing example
# safe_write "$HOOK" <<'EOF'
# #!/bin/sh
# SHA=$(cat "$BARE_REPO/refs/heads/master")
# su - $OBS_USER -c "/usr/local/bin/git --git-dir=$BARE_REPO --work-tree=$WORK_DIR checkout -f $SHA"
# exit 0
# EOF

# Idempotency: replace+template with checksum example
# tmp_hook="$(mktemp)"
# cat > "$tmp_hook" <<'EOF'
# #!/bin/sh
# SHA=$(cat "$BARE_REPO/refs/heads/master")
# su - $OBS_USER -c "/usr/local/bin/git --git-dir=$BARE_REPO --work-tree=$WORK_DIR checkout -f $SHA"
# exit 0
# EOF
# old_sum="$(sha256 -q "$HOOK" 2>/dev/null || true)"
# new_sum="$(sha256 -q "$tmp_hook")"
# [ "$old_sum" = "$new_sum" ] || mv "$tmp_hook" "$HOOK"
# rm -f "$tmp_hook"
cat > "$HOOK" <<EOF
#!/bin/sh
SHA=\$(cat "$BARE_REPO/refs/heads/master")
su - $OBS_USER -c "/usr/local/bin/git --git-dir=$BARE_REPO --work-tree=$WORK_DIR checkout -f \$SHA"
exit 0
EOF

# Idempotency: rollback handling and dry-run mode example
# run_cmd "chown ${GIT_USER}:${GIT_USER} $HOOK" "chown root:wheel $HOOK"
chown "${GIT_USER}:${GIT_USER}" "$HOOK"
# Idempotency: rollback handling and dry-run mode example
# run_cmd "chmod +x $HOOK" "chmod -x $HOOK"
chmod +x "$HOOK"

##############################################################################
# 11) Working copy clone & initial commit
##############################################################################

# TODO: Idempotency: state detection

# Idempotency: rollback handling and dry-run mode example
# run_cmd "mkdir -p $(dirname $WORK_DIR)" "rmdir $(dirname $WORK_DIR)"
mkdir -p "$(dirname "$WORK_DIR")"
# TODO: Idempotency: state detection

# Idempotency: rollback handling and dry-run mode example
# run_cmd "git -c safe.directory=$BARE_REPO clone $BARE_REPO $WORK_DIR" "rm -rf $WORK_DIR"
git -c safe.directory="$BARE_REPO" clone "$BARE_REPO" "$WORK_DIR"
# Idempotency: rollback handling and dry-run mode example
# run_cmd "chown -R ${OBS_USER}:${OBS_USER} $WORK_DIR" "chown -R root:wheel $WORK_DIR"
chown -R "${OBS_USER}:${OBS_USER}" "$WORK_DIR"

# Idempotency: rollback handling and dry-run mode example
  # run_cmd "git -C $WORK_DIR -c safe.directory=$WORK_DIR -c user.name='Obsidian User' -c user.email='obsidian@example.com' commit --allow-empty -m 'initial commit'" "git -C $WORK_DIR reset --hard HEAD~1"
  git -C "$WORK_DIR" \
      -c safe.directory="$WORK_DIR" \
      -c user.name='Obsidian User' \
      -c user.email='obsidian@example.com' \
      commit --allow-empty -m 'initial commit'

##############################################################################
# 12) Final perms on bare repo
##############################################################################

# Idempotency: rollback handling and dry-run mode example
# run_cmd "git --git-dir=$BARE_REPO config core.sharedRepository group" "git --git-dir=$BARE_REPO config --unset core.sharedRepository"
git --git-dir="$BARE_REPO" config core.sharedRepository group
# Idempotency: rollback handling and dry-run mode example
# run_cmd "chown -R ${GIT_USER}:vault $BARE_REPO" "chown -R root:wheel $BARE_REPO"
chown -R "${GIT_USER}:vault" "$BARE_REPO"
# Idempotency: rollback handling and dry-run mode example
# run_cmd "chmod -R g+rwX $BARE_REPO" "chmod -R go-rwx $BARE_REPO"
chmod -R g+rwX "$BARE_REPO"
# Idempotency: rollback handling and dry-run mode example
# run_cmd "find $BARE_REPO -type d -exec chmod g+s {} +" "find $BARE_REPO -type d -exec chmod g-s {} +"
find "$BARE_REPO" -type d -exec chmod g+s {} +

##############################################################################
# 13) History settings (.profile)
##############################################################################

for u in "$OBS_USER" "$GIT_USER"; do
  PROFILE="/home/$u/.profile"
      # TODO: Idempotency: state detection
      
      # Idempotency: rollback handling and dry-run mode example
      # run_cmd "cat >> $PROFILE" "cp ${PROFILE}.bak $PROFILE"

      # Idempotency: safe editing example
      # safe_append_line "$PROFILE" "export HISTFILE=/home/$u/.ksh_history"
      # safe_append_line "$PROFILE" "export HISTSIZE=5000"
      # safe_append_line "$PROFILE" "export HISTCONTROL=ignoredups"

# Idempotency: replace+template with checksum example
# tmp_profile="$(mktemp)"
# cat "$PROFILE" > "$tmp_profile" 2>/dev/null || true
# cat >> "$tmp_profile" <<EOF
# export HISTFILE=/home/$u/.ksh_history
# export HISTSIZE=5000
# export HISTCONTROL=ignoredups
# EOF
# old_sum="$(sha256 -q "$PROFILE" 2>/dev/null || true)"
# new_sum="$(sha256 -q "$tmp_profile")"
# [ "$old_sum" = "$new_sum" ] || mv "$tmp_profile" "$PROFILE"
# rm -f "$tmp_profile"
      cat <<EOF >> "$PROFILE"
export HISTFILE=/home/$u/.ksh_history
export HISTSIZE=5000
export HISTCONTROL=ignoredups
EOF
    # Idempotency: rollback handling and dry-run mode example
    # run_cmd "chown $u:$u $PROFILE" "chown root:wheel $PROFILE"
    chown "$u:$u" "$PROFILE"
done

echo "obsidian-git-host: Vault setup complete!"
