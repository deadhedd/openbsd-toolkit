#!/bin/sh
#
# setup_obsidian_git.sh - Git-backed Obsidian vault setup
# Usage: ./setup_obsidian_git.sh [--log[=FILE]] [-h]
#

set -x

#
# 1) Find where this script lives, even if invoked via PATH or "sh script.sh"
#
case "$0" in
  */*) SCRIPT_PATH="$0" ;;
  *)   SCRIPT_PATH="$(command -v -- "$0" 2>/dev/null || printf "%s" "$0")" ;;
esac
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"

#
# 2) Logging defaults
#
FORCE_LOG=0
LOGFILE=""

#
# 3) Usage helper
#
usage() {
  cat <<EOF
Usage: $0 [--log[=FILE]] [-h]

  --log, -l       Capture stdout, stderr & xtrace into:
                   \${SCRIPT_DIR%/scripts}/logs/$(basename "$0" .sh)-TIMESTAMP.log
                 Or use --log=FILE to choose a custom path.

  -h, --help      Show this help and exit.
EOF
  exit 0
}

#
# 4) Parse flags
#
while [ $# -gt 0 ]; do
  case "$1" in
    -l|--log)        FORCE_LOG=1             ;;
    -l=*|--log=*)    FORCE_LOG=1; LOGFILE="${1#*=}" ;;
    -h|--help)       usage                   ;;
    *)               echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

#
# 5) Centralized logging init
#
PROJECT_ROOT="${SCRIPT_DIR%/scripts}"
LOG_HELPER="$PROJECT_ROOT/logs/logging.sh"
[ -f "$LOG_HELPER" ] || { echo "❌ logging.sh not found at $LOG_HELPER" >&2; exit 1; }
. "$LOG_HELPER"
init_logging "$0"

#
# 6) Load secrets
#
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$PROJECT_ROOT/config/load_secrets.sh"

#
# 7) Vault-setup logic
#

# Ensure OBS_USER, GIT_USER, and VAULT are set
: "${OBS_USER:?OBS_USER must be set in secrets}"
: "${GIT_USER:?GIT_USER must be set in secrets}"
: "${VAULT:?VAULT must be set in secrets}"

# 1. Install Git
pkg_add -v git

# 2. Helper to remove password from master.passwd
remove_password() {
  user="$1"
  tmp=$(mktemp)
  sed -E "s/^${user}:[^:]*:/${user}::/" /etc/master.passwd >"$tmp"
  mv "$tmp" /etc/master.passwd
  pwd_mkdb -p /etc/master.passwd
}

# 3. Create OBS_USER and GIT_USER
for u in "$OBS_USER" "$GIT_USER"; do
  shell_path="$( [ "$u" = "$OBS_USER" ] && printf '/bin/ksh' || printf '/usr/local/bin/git-shell' )"
  if ! id "$u" >/dev/null 2>&1; then
    useradd -m -s "$shell_path" "$u"
    pass_var="${u^^}_PASS"  # e.g. OBS_PASS or GIT_PASS
    if eval "[ -n \"\${$pass_var}\" ]"; then
      eval "printf '%s\n' \"\${$pass_var}\" | passwd $u"
    else
      remove_password "$u"
    fi
  fi
done

# 4. Configure doas
cat >/etc/doas.conf <<-EOF
permit persist ${OBS_USER} as root
permit nopass  ${GIT_USER} as root cmd git*
EOF
chown root:wheel /etc/doas.conf
chmod 0440       /etc/doas.conf

# 5. Harden SSH: allow only these users
if grep -q '^AllowUsers ' /etc/ssh/sshd_config; then
  sed -i "/^AllowUsers /c\\AllowUsers ${OBS_USER} ${GIT_USER}" /etc/ssh/sshd_config
else
  echo "AllowUsers ${OBS_USER} ${GIT_USER}" >>/etc/ssh/sshd_config
fi
rcctl restart sshd

# 6. Setup SSH dirs & known_hosts
for u in "$OBS_USER" "$GIT_USER"; do
  homedir="/home/$u"
  sshdir="$homedir/.ssh"
  mkdir -p "$sshdir"
  chmod 700 "$sshdir"
  touch "$sshdir/authorized_keys"
  chmod 600 "$sshdir/authorized_keys"
  chown -R "$u:$u" "$sshdir"
done

ssh-keyscan -H "${SERVER}" >>"/home/${OBS_USER}/.ssh/known_hosts"
chmod 644 "/home/${OBS_USER}/.ssh/known_hosts"
chown "$OBS_USER:$OBS_USER" "/home/${OBS_USER}/.ssh/known_hosts"

# 7. Bare repo under GIT_USER
vault_dir="/home/${GIT_USER}/vaults"
bare_repo="$vault_dir/${VAULT}.git"
mkdir -p "$vault_dir"; chown "$GIT_USER:$GIT_USER" "$vault_dir"
git init --bare "$bare_repo"; chown -R "$GIT_USER:$GIT_USER" "$bare_repo"

# 8. Git safe.directory entries
for u in "$GIT_USER" "$OBS_USER"; do
  cfg="/home/$u/.gitconfig"
  touch "$cfg"
  safe_path="$([ "$u" = "$GIT_USER" ] && printf "$bare_repo" || printf "/home/$OBS_USER/vaults/$VAULT")"
  git config --file "$cfg" --add safe.directory "$safe_path"
  chown "$u:$u" "$cfg"
done

# 9. Post-receive hook
hook="$bare_repo/hooks/post-receive"
cat >"$hook" <<-EOF
#!/bin/sh
git --work-tree="/home/${OBS_USER}/vaults/${VAULT}" \\
    --git-dir="$bare_repo" checkout -f
exit 0
EOF
chown "$GIT_USER:$GIT_USER" "$hook"
chmod +x "$hook"

# 10. Clone working copy for OBS_USER
work_dir="/home/${OBS_USER}/vaults/$VAULT"
mkdir -p "$(dirname "$work_dir")"
git clone "$bare_repo" "$work_dir"
chown -R "$OBS_USER:$OBS_USER" "$work_dir"

# 11. Initial empty commit
cd "$work_dir"
git -c user.name='Obsidian User' \
    -c user.email='obsidian@example.com' \
    commit --allow-empty -m 'initial commit'

# 12. Setup history in .profile
for u in "$OBS_USER" "$GIT_USER"; do
  profile="/home/$u/.profile"
  cat <<-EOF >>"$profile"
export HISTFILE=/home/$u/.ksh_history
export HISTSIZE=5000
export HISTCONTROL=ignoredups
EOF
  chown "$u:$u" "$profile"
done

echo "✅ Obsidian sync setup complete."

