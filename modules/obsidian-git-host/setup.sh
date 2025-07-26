#!/bin/sh
#
# setup.sh — Git-backed Obsidian vault setup (obsidian-git-host module)
# Usage: ./setup.sh [--debug[=FILE]] [-h]

##############################################################################
# 1) Determine script & project paths
##############################################################################
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export PROJECT_ROOT

##############################################################################
# 2) Load logging system and parse --debug
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
# 3) Load secrets (must define OBS_USER, GIT_USER, VAULT, GIT_SERVER)
##############################################################################
. "$PROJECT_ROOT/config/load_secrets.sh"
: "${OBS_USER:?OBS_USER must be set in secrets}"
: "${GIT_USER:?GIT_USER must be set in secrets}"
: "${VAULT:?VAULT must be set in secrets}"
: "${GIT_SERVER:?GIT_SERVER must be set in secrets}"

##############################################################################
# 4) Install Git
##############################################################################
pkg_add -v git

##############################################################################
# 5) Helper to remove password from master.passwd
##############################################################################
remove_password() {
  user="$1"
  tmp=$(mktemp)
  sed -E "s|^${user}:[^:]*:|${user}::|" /etc/master.passwd >"$tmp"
  mv "$tmp" /etc/master.passwd
  pwd_mkdb -p /etc/master.passwd
}

##############################################################################
# 6) Create OBS_USER and GIT_USER
##############################################################################
for u in "$OBS_USER" "$GIT_USER"; do
  shell_path=$([ "$u" = "$OBS_USER" ] && echo '/bin/ksh' || echo '/usr/local/bin/git-shell')
  if ! id "$u" >/dev/null 2>&1; then
    useradd -m -s "$shell_path" "$u"
    pass_var="$(echo "$u" | tr '[:lower:]' '[:upper:]')_PASS"
    if eval "[ -n \"\${$pass_var}\" ]"; then
      eval "printf '%s\n' \"\${$pass_var}\" | passwd $u"
    else
      remove_password "$u"
    fi
  fi
done

##############################################################################
# 7) Create shared group and add users
##############################################################################
groupadd vault || true
usermod -G vault "$OBS_USER"
usermod -G vault "$GIT_USER"

##############################################################################
# 8) Configure doas
##############################################################################
cat > /etc/doas.conf <<-EOF
permit persist ${OBS_USER} as root
permit nopass ${GIT_USER} as root cmd git*
permit nopass ${GIT_USER} as ${OBS_USER} cmd git*
EOF
chown root:wheel /etc/doas.conf
chmod 0440 /etc/doas.conf

##############################################################################
# 9) Harden SSH to allow only OBS_USER & GIT_USER
##############################################################################
if grep -q '^AllowUsers ' /etc/ssh/sshd_config; then
  sed -i "/^AllowUsers /c\\AllowUsers ${OBS_USER} ${GIT_USER}" /etc/ssh/sshd_config
else
  echo "AllowUsers ${OBS_USER} ${GIT_USER}" >> /etc/ssh/sshd_config
fi
rcctl restart sshd

##############################################################################
# 10) Setup SSH dirs & known_hosts for both users
##############################################################################
for u in "$OBS_USER" "$GIT_USER"; do
  homedir="/home/$u"
  sshdir="$homedir/.ssh"
  mkdir -p "$sshdir"
  chmod 700 "$sshdir"
  touch "$sshdir/authorized_keys"
  chmod 600 "$sshdir/authorized_keys"
  chown -R "$u:$u" "$sshdir"
done

ssh-keyscan -H "$GIT_SERVER" >> "/home/${OBS_USER}/.ssh/known_hosts"
chmod 644 "/home/${OBS_USER}/.ssh/known_hosts"
chown "${OBS_USER}:${OBS_USER}" "/home/${OBS_USER}/.ssh/known_hosts"

##############################################################################
# 11) Initialize bare repo under GIT_USER
##############################################################################
vault_dir="/home/${GIT_USER}/vaults"
bare_repo="${vault_dir}/${VAULT}.git"
mkdir -p "$vault_dir"
chown "${GIT_USER}:${GIT_USER}" "$vault_dir"

git init --bare "$bare_repo"
chown -R "${GIT_USER}:${GIT_USER}" "$bare_repo"

##############################################################################
# 12) Configure Git safe.directory for both users
##############################################################################
for u in "$GIT_USER" "$OBS_USER"; do
  cfg="/home/$u/.gitconfig"
  touch "$cfg"
  if [ "$u" = "$GIT_USER" ]; then
    git config --file "$cfg" --add safe.directory "$bare_repo"
    git config --file "$cfg" --add safe.directory "/home/${OBS_USER}/vaults/${VAULT}"
  else
    git config --file "$cfg" --add safe.directory "/home/${OBS_USER}/vaults/${VAULT}"
  fi
  chown "$u:$u" "$cfg"
done

##############################################################################
# 13) Create post-receive hook to update working copy
##############################################################################
work_dir="/home/${OBS_USER}/vaults/${VAULT}"
hook="$bare_repo/hooks/post-receive"

cat > "$hook" <<-EOF
#!/bin/sh
SHA=\$(cat "$bare_repo/refs/heads/master")
su - $OBS_USER -c "/usr/local/bin/git --git-dir=$bare_repo --work-tree=$work_dir checkout -f \$SHA"
exit 0
EOF

chown "${GIT_USER}:${GIT_USER}" "$hook"
chmod +x "$hook"

##############################################################################
# 14) Clone working copy for OBS_USER
##############################################################################
mkdir -p "$(dirname "$work_dir")"
git -c safe.directory="$bare_repo" clone "$bare_repo" "$work_dir"
chown -R "${OBS_USER}:${OBS_USER}" "$work_dir"

##############################################################################
# 15) Make initial empty commit
##############################################################################
git -C "$work_dir" \
    -c safe.directory="$work_dir" \
    -c user.name='Obsidian User' \
    -c user.email='obsidian@example.com' \
    commit --allow-empty -m 'initial commit'

##############################################################################
# 16) Configure history settings in users' .profile
##############################################################################
for u in "$OBS_USER" "$GIT_USER"; do
  profile="/home/$u/.profile"
  cat <<-EOF >> "$profile"
export HISTFILE=/home/$u/.ksh_history
export HISTSIZE=5000
export HISTCONTROL=ignoredups
EOF
  chown "$u:$u" "$profile"
done

##############################################################################
# 17) Fix permissions on bare repo for group collaboration
##############################################################################
chown -R "${GIT_USER}:vault" "$bare_repo"
chmod -R g+rwX "$bare_repo"
find "$bare_repo" -type d -exec chmod g+s {} +
git --git-dir="$bare_repo" config core.sharedRepository group

echo "✅ obsidian-git-host: Vault setup complete."
