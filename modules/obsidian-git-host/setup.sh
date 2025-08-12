commit a0151949f9491cc43f3fb946b802d4a3955f698b
Author: deadhedd <167578248+deadhedd@users.noreply.github.com>
Date:   Fri Aug 8 06:19:30 2025 -0700

    Remove service account SSH setup

diff --git a/modules/obsidian-git-host/setup.sh b/modules/obsidian-git-host/setup.sh
index a8f6dcd..d21290f 100644
--- a/modules/obsidian-git-host/setup.sh
+++ b/modules/obsidian-git-host/setup.sh
@@ -13,7 +13,7 @@
 #
 # Deployment considerations:
 #   Requires these vars (exported via config/load-secrets.sh):
-#     • OBS_USER, GIT_USER, VAULT, GIT_SERVER
+#     • OBS_USER, GIT_USER, VAULT
 #   Assumes pkg_add git is available and run as root on OpenBSD.
 #
 # Security note:
@@ -149,7 +149,6 @@ start_logging_if_debug "setup-$module_name" "$@"
 : "${OBS_USER:?OBS_USER must be set in secrets}"
 : "${GIT_USER:?GIT_USER must be set in secrets}"
 : "${VAULT:?VAULT must be set in secrets}"
-: "${GIT_SERVER:?GIT_SERVER must be set in secrets}"
 
 ##############################################################################
 # 4) Packages
@@ -209,69 +208,14 @@ chown root:wheel /etc/doas.conf
 chmod 0440 /etc/doas.conf
 
 ##############################################################################
-# 7) SSH hardening & per-user SSH dirs
+# 7) SSH hardening
 ##############################################################################
 
-# 7.1 SSH Service & Config
-safe_replace_line /etc/ssh/sshd_config "AllowUsers" "${ADMIN_USER} ${OBS_USER} ${GIT_USER}"
+safe_replace_line /etc/ssh/sshd_config "AllowUsers" "${ADMIN_USER}"
 # Idempotency: rollback handling and dry-run mode example
 # run_cmd "rcctl restart sshd" "rcctl restart sshd"
 rcctl restart sshd
 
-# 7.2 .ssh Directories and authorized users
-for u in "$OBS_USER" "$GIT_USER"; do
-  HOME_DIR="/home/$u"
-  SSH_DIR="$HOME_DIR/.ssh"
-    
-    # Idempotency: rollback handling and dry-run mode example
-    # run_cmd "mkdir -p $SSH_DIR" "rmdir $SSH_DIR"
-    
-    # Idempotency: state detection example
-    # [ -d "$SSH_DIR" ] || mkdir -p "$SSH_DIR"
-    mkdir -p "$SSH_DIR"
-    # Idempotency: rollback handling and dry-run mode example
-    # run_cmd "chmod 700 $SSH_DIR" "chmod 755 $SSH_DIR"
-    chmod 700 "$SSH_DIR"
-    
-    # Idempotency: rollback handling and dry-run mode example
-    # run_cmd "touch $SSH_DIR/authorized_keys" "rm -f $SSH_DIR/authorized_keys"
-    
-    # Idempotency: state detection example
-    # [ -f "$SSH_DIR/authorized_keys" ] || touch "$SSH_DIR/authorized_keys"
-    touch "$SSH_DIR/authorized_keys"
-    # Idempotency: rollback handling and dry-run mode example
-    # run_cmd "chmod 600 $SSH_DIR/authorized_keys" "chmod 644 $SSH_DIR/authorized_keys"
-    chmod 600 "$SSH_DIR/authorized_keys"
-    # Idempotency: rollback handling and dry-run mode example
-    # run_cmd "chown -R $u:$u $SSH_DIR" "chown -R root:wheel $SSH_DIR"
-    chown -R "$u:$u" "$SSH_DIR"
-done
-
-# 7.3 Known Hosts (OBS_USER only)
-# TODO: Idempotency: state detection
-
-# Idempotency: rollback handling and dry-run mode example
-# run_cmd "ssh-keyscan -H $GIT_SERVER >> /home/${OBS_USER}/.ssh/known_hosts" "sed -i '/$GIT_SERVER/d' /home/${OBS_USER}/.ssh/known_hosts"
-
-# Idempotency: safe editing example
-# safe_append_line "/home/${OBS_USER}/.ssh/known_hosts" "$(ssh-keyscan -H $GIT_SERVER)"
-
-# Idempotency: replace+template with checksum example
-# tmp_hosts="$(mktemp)"
-# cat "/home/${OBS_USER}/.ssh/known_hosts" > "$tmp_hosts" 2>/dev/null || true
-# ssh-keyscan -H "$GIT_SERVER" >> "$tmp_hosts"
-# old_sum="$(sha256 -q /home/${OBS_USER}/.ssh/known_hosts 2>/dev/null || true)"
-# new_sum="$(sha256 -q "$tmp_hosts")"
-# [ "$old_sum" = "$new_sum" ] || mv "$tmp_hosts" "/home/${OBS_USER}/.ssh/known_hosts"
-# rm -f "$tmp_hosts"
-ssh-keyscan -H "$GIT_SERVER" >> "/home/${OBS_USER}/.ssh/known_hosts"
-# Idempotency: rollback handling and dry-run mode example
-# run_cmd "chmod 644 /home/${OBS_USER}/.ssh/known_hosts" "chmod 600 /home/${OBS_USER}/.ssh/known_hosts"
-chmod 644 "/home/${OBS_USER}/.ssh/known_hosts"
-# Idempotency: rollback handling and dry-run mode example
-# run_cmd "chown ${OBS_USER}:${OBS_USER} /home/${OBS_USER}/.ssh/known_hosts" "chown root:wheel /home/${OBS_USER}/.ssh/known_hosts"
-chown "${OBS_USER}:${OBS_USER}" "/home/${OBS_USER}/.ssh/known_hosts"
-
 ##############################################################################
 # 8) Repo paths & bare init
 ##############################################################################
