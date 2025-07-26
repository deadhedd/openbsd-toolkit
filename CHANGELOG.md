## 🚀 v0.9.0 – Permissions & Hook Improvements (2025-07-18)

* **Permissions & Git config**

  * Configured Git’s `safe.directory` to allow operations in our bare repo without warnings.
  * Created a shared Unix group for the `git` and `obsidian` users to streamline permissions.
  * Enforced proper file permissions and ownership on the bare repository (`git:obsidian` with `g+rwX` and `setgid` on directories).
  * Added `sharedRepository = group` under `[core]` in the bare repo’s Git config for group-write support.
* **Fixes**

  * Corrected the post‑receive hook so that the commit SHA is captured literally and the working-tree checkout runs under the `obsidian` user.
* **Logging**

  * Enhanced logging across both setup and test scripts for improved traceability.

---

## 🚀 v0.4.0 – Centralized Secrets Management (2025-07-06)

* **Secrets management**

  * Introduced centralized `.env`-style `secrets.env` support, loading defaults from `secrets.env.example`.
  * Bootstrap step: auto-generate `secrets.env` when missing, with user notification.
  * All setup and test scripts now source configuration from `secrets.env` instead of hardcoded values.

---

## 🚀 v0.3 – Configuration & Test Coverage Completion (2025-07-02)

* **Test runner reliability**

  * `test_all.sh` now continues through all suites even if one fails, so you get a full report in one run.

* **test\_github additions**

  * Verifies `/root/.ssh` exists.
  * Confirms the repository is cloned into `$setup_dir/.git`.
  * Checks `remote origin` in `$setup_dir/.git/config` matches `$GITHUB_REPO`.

* **test\_system enhancements**

  * Asserts `${INTERFACE}` is up with `${STATIC_IP}`.
  * Ensures `PasswordAuthentication no` in `/etc/ssh/sshd_config`.
  * Validates root’s `.profile` exports:

    * `HISTFILE=/root/.ksh_history`
    * `HISTSIZE=5000`
    * `HISTCONTROL=ignoredups`

* **History‑merge test**

  * Confirms old‑history marker is merged into new history.
  * Confirms new‑history marker remains intact.

* **doas & package tests moved**

  * Package installation and `doas.conf` permission/ownership tests are now in `test_obsidian_git.sh`.

* **test\_obsidian\_git expanded**

  * SSH service config (`AllowUsers`, daemon running).
  * `.ssh` directories and `authorized_keys` for both `git` and `obsidian` users (existence, perms, ownership).
  * Vaults directories for both users.
  * Bare repo HEAD, `safe.directory` entries, post‑receive hook shebang & content.
  * Working‑clone verification (clone, remote URL, commit presence).
  * Per‑user history settings in `.profile` and `master.passwd` (password removal or setting).

* **Setup scripts aligned**

  * Added or moved all corresponding configuration blocks into `setup_system.sh` and `setup_obsidian_git.sh` so new tests pass out-of-the-box.

---
