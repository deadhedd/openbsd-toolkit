# openbsd-server

A collection of modular scripts to configure and validate an OpenBSD server for hosting a Git-backed Obsidian vault, with support for GitHub deploy key integration.

---

## 🚀 v0.3 – Configuration & Test Coverage Completion (2025-07-02)

* **Test runner reliability**

  * `test_all.sh` now continues through all suites even if one fails, so you get a full report in one run.

* **test_github additions**

  * Verifies `/root/.ssh` exists.  
  * Confirms the repository is cloned into `$setup_dir/.git`.  
  * Checks `remote origin` in `$setup_dir/.git/config` matches `$GITHUB_REPO`.

* **test_system enhancements**

  * Asserts `${INTERFACE}` is up with `${STATIC_IP}`.  
  * Ensures `PasswordAuthentication no` in `/etc/ssh/sshd_config`.  
  * Validates root’s `.profile` exports:  
    - `HISTFILE=/root/.ksh_history`  
    - `HISTSIZE=5000`  
    - `HISTCONTROL=ignoredups`

* **History‑merge test**

  * Confirms old‑history marker is merged into new history.  
  * Confirms new‑history marker remains intact.

* **doas & package tests moved**

  * Package installation and `doas.conf` permission/ownership tests are now in `test_obsidian_git.sh`.

* **test_obsidian_git expanded**

  * SSH service config (`AllowUsers`, daemon running).  
  * `.ssh` directories and `authorized_keys` for both `git` and `obsidian` users (existence, perms, ownership).  
  * Vaults directories for both users.  
  * Bare repo HEAD, `safe.directory` entries, post‑receive hook shebang & content.  
  * Working‑clone verification (clone, remote URL, commit presence).  
  * Per‑user history settings in `.profile` and `master.passwd` (password removal or setting).

* **Setup scripts aligned**

  * Added or moved all corresponding configuration blocks into `setup_system.sh` and `setup_obsidian_git.sh` so new tests pass out-of-the-box.

---

## 📋 Prerequisites

* **OS:** OpenBSD (tested on 7.x)

---

## ⚙️ Scripts Overview

### Setup Scripts

| Script                  | Purpose                                                                                               |
| ----------------------- | ----------------------------------------------------------------------------------------------------- |
| `setup_system.sh`       | Installs packages, creates users, sets up networking and doas, hardens SSH, configures user profiles. |
| `setup_obsidian_git.sh` | Initializes the Git bare repo and working copy for Obsidian vault syncing.                            |
| `setup_github.sh`       | Installs deploy key and bootstraps the GitHub repo clone for ongoing configuration management.        |
| `setup_all.sh`          | Runs all of the above in sequence.                                                                    |

### Test Suites

| Script                 | Validates                                                         |
| ---------------------- | ----------------------------------------------------------------- |
| `test_system.sh`       | User setup, file permissions, doas, network, DNS, SSH security.   |
| `test_obsidian_git.sh` | Git bare repo structure, safe.directory flags, post-receive hook. |
| `test_github.sh`       | Deploy key presence and permission, GitHub in known\_hosts.       |
| `test_all.sh`          | Runs all of the above in sequence, with optional logging.         |

---

## 📝 Usage & Logging

All setup and test scripts support optional logging flags:

* **Force a log on every run**:

  ```sh
  ./script.sh --log
  ./script.sh -l
````

* **Specify a custom logfile**:

  ```sh
  ./script.sh --log=/path/to/my.log
  ```

* **Default behavior**:

  * Logs only on **failure**, written to `logs/<script>-YYYYMMDD_HHMMSS.log`.

### Run all setup steps

```sh
sh setup_all.sh
```

Override defaults using environment variables:

```sh
REG_USER=obsidian \
GIT_USER=git \
VAULT=myvault \
INTERFACE=em0 \
STATIC_IP=192.0.2.10 \
NETMASK=255.255.255.0 \
GATEWAY=192.0.2.1 \
sh setup_all.sh
```

Or run individual setup phases:

```sh
sh setup_system.sh
sh setup_obsidian_git.sh
sh setup_github.sh
```

### Run all test suites

```sh
sh test_all.sh [--log[=FILE]]
```

Same environment variables apply.

---

## 🔖 Releases & Tags

Use version tags to snapshot working configurations:

```sh
git tag -a v0.3 -m "v0.3 – Configuration & Test Coverage Completion"
git push origin --tags
```

---

## 📜 Changelog

### v0.3 – Configuration & Test Coverage Completion (2025-07-02)

* **Test runner reliability**

  * `test_all.sh` now continues through all suites even if one fails.

* **test\_github additions**

  * Verified `/root/.ssh` exists.
  * Confirmed repo clone into `$setup_dir`.
  * Checked `remote origin` URL in `.git/config`.

* **test\_system enhancements**

  * Asserted `${INTERFACE}` IP assignment.
  * Ensured SSH disallows password auth.
  * Root’s `.profile` now exports `HISTFILE`, `HISTSIZE`, and `HISTCONTROL`.

* **History‑merge test**

  * Old history merged into new.
  * New history preserved.

* **doas & package tests moved**

  * Tests for package installation and `doas.conf` perms/ownership now live in `test_obsidian_git.sh`.

* **test\_obsidian\_git expanded**

  * SSHD config & daemon checks.
  * `.ssh` and `authorized_keys` validation for both users.
  * Vaults directory existence and permissions.
  * Bare repo HEAD, `safe.directory`, post‑receive hook content.
  * Working clone functionality (clone, remote URL, commit log).
  * Per-user history and password‑field tests in `master.passwd`.

* **Setup scripts aligned**

  * Added all corresponding config snippets to `setup_system.sh` and `setup_obsidian_git.sh`.

### 🚀 v0.2.1 – Usability Improvements (2025-06-28)

* **Logging Enhancements**

  * `--log[=FILE]` / `-l`: force writing a full log on every run.
  * Sensible defaults: logs written to `logs/` with timestamped filenames.

* **Expanded User Setup**

  * Configures **both** `git` and `obsidian` users (instead of only `git`).
  * Blank initial passwords assigned for both users (can be pulled from a secrets file).
  * Fixed the bug in `setup_obsidian_git.sh` that this change introduced.

* **Refactor Sync Code**

  * Moved missing code blocks from `setup_all.sh` into `setup_obsidian_git.sh`.
  * Mirrored those changes in the corresponding test scripts for consistency.

### v0.2.0 – Modularization (2025-06-26)

* **Split monolithic setup/test scripts** into:

  * `setup_system.sh`
  * `setup_obsidian_git.sh`
  * `setup_github.sh`
  * `test_system.sh`
  * `test_obsidian_git.sh`
  * `test_github.sh`
* Added `setup_all.sh` and `test_all.sh` for convenience.

### v0.1.1 – Test Enhancements (2025-06-23)

* Added strict validation for network config files.
* Anchored regex to prevent deprecated `netmask` lines.
* Retained all core tests from v0.1.

### v0.1 – Initial Release

* Setup and validation for OpenBSD server configuration (users, SSH, network, Git).

---

## License

MIT OR 0BSD — see the LICENSE file.

```
