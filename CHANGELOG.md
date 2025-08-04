# 📋 Changelog

All notable changes to this project will be documented in this file following [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) principles.

---

## Unreleased

### Logging and Debugging

* Dropped `set -v` from test scripts, now using `set -x` while setup scripts
  continue to leverage `set -vx` for expanded command logging.
* Added support for `--debug=FILE` to direct debug output to a custom log file.

### Base System Setup

* Root account `authorized_keys` now populated from `ROOT_SSH_PUBLIC_KEY_FILES`,
  enabling multiple keys to be provisioned during setup.

### GitHub Module

* GitHub module now reads SSH key filenames from `secrets.env` (`GITHUB_SSH_PRIVATE_KEY_FILE` and `GITHUB_SSH_PUBLIC_KEY_FILE`) instead of using a hardcoded deploy key.

## v1.0 – Initial Stable Release (2025-07-26)

### Setup and Tests

* **User Password Simplification**

  * Replaced the old `remove_password()` logic with a much simpler blank password setup for `git` and `obsidian` users.

* **Git Safe Directory and `-C` Option**

  * Cleaned up Git commands by switching to the `-C` option instead of `cd` for safer, cleaner directory handling.

* **Shared Repository Config**

  * Ensured `core.sharedRepository = group` is automatically set in bare repo configs.

### Logging and Debugging

* **Debug Flag Behavior**

  * Updated debug logs to use `set -vx`, ensuring both executed commands and their expanded values are included.

* **ASCII-Only Output**

  * Restricted script output to plain ASCII for OpenBSD terminal compatibility.

### Code Cleanups

* **ShellCheck Pass**

  * Addressed multiple ShellCheck warnings (unused vars, array-to-string assignments, variable path sourcing).

* **Help Flag Standardization**

  * Updated `--help`/`-h` messages and ensured consistent flag parsing across all scripts.

* **Author and Header Consistency**

  * Normalized file headers (`Author: deadhedd`) and comments.

### Structure and Misc

* **Pre-1.0 Polish**

  * Consolidated redundant user creation logic.
  * Polished `setup.sh` and `install-modules.sh` usage text and logging defaults.

---

## v0.9.2 – Setup Script Fixes + Logging Update Pre-release (2025-07-24)

### Fixes

* Resolved regressions in setup scripts caused by partial logging system migration.
* All setup scripts now correctly use the centralized logging system.

### Breaking Change

* The `--log` flag is no longer supported in setup scripts.
* Use `--debug` if you want full output logged to a file.

---

## v0.9.1 – Enhanced Logging and Project Cleanup (Pre-release) (2025-07-23)

### Highlights

#### Enhanced Logging Subsystem

* Centralized logging implementation using FIFO + `tee`
* Captures `set -x` traces for full debug visibility
* Optional log buffering with `--log` / `--debug` flags
* Per-module test logs written automatically

#### Project Structure Overhaul

* Renamed directories for clarity (e.g. `scripts/`, `modules/`, etc.)
* Improved layout for testing and setup modules
* Cleaner repo organization for contributors and automation

---

## v0.9.0 – Permissions & Hook Improvements (2025-07-18)

### Permissions and Git Configuration

* Configured Git’s `safe.directory` to allow operations in our bare repo without warnings.
* Created a shared Unix group for the `git` and `obsidian` users to streamline permissions.
* Enforced proper file permissions and ownership on the bare repository (`git:obsidian` with `g+rwX` and `setgid` on directories).
* Added `sharedRepository = group` under `[core]` in the bare repo’s Git config for group-write support.

### Fixes

* Corrected the `post-receive` hook so that the commit SHA is captured literally and the working-tree checkout runs under the `obsidian` user.

### Logging

* Enhanced logging across both setup and test scripts for improved traceability.

---

## v0.4.0 – Centralized Secrets Management (2025-07-06)

### Secrets Management

* Introduced centralized `.env`-style `secrets.env` support, loading defaults from `secrets.env.example`.
* Bootstrap step: auto-generates `secrets.env` when missing, with user notification.
* All setup and test scripts now source configuration from `secrets.env` instead of hardcoded values.

---

## v0.3 – Configuration & Test Coverage Completion (2025-07-02)

### Test Runner Reliability

* `test-all.sh` now continues through all suites even if one fails, so you get a full report in one run.

### GitHub Test Additions

* Verifies `/root/.ssh` exists.
* Confirms the repository is cloned into `$setup_dir/.git`.
* Checks remote origin in `$setup_dir/.git/config` matches `$GITHUB_REPO`.

### System Test Enhancements

* Asserts `${INTERFACE}` is up with `${STATIC_IP}`.
* Ensures `PasswordAuthentication no` in `/etc/ssh/sshd_config`.
* Validates root’s `.profile` exports:

  * `HISTFILE=/root/.ksh_history`
  * `HISTSIZE=5000`
  * `HISTCONTROL=ignoredups`

### History Merge Test

* Confirms `old-history` marker is merged into new history.
* Confirms `new-history` marker remains intact.

### Package and Doas Test Relocation

* Package installation and `doas.conf` permission/ownership tests are now in `test-obsidian-git.sh`.

### Obsidian Git Test Expansion

* SSH service config (`AllowUsers`, daemon running).
* `.ssh` directories and `authorized_keys` for both `git` and `obsidian` users (existence, perms, ownership).
* Vaults directories for both users.
* Bare repo `HEAD`, `safe.directory` entries, `post-receive` hook shebang & content.
* Working-clone verification (clone, remote URL, commit presence).
* Per-user history settings in `.profile` and `master.passwd` (password removal or setting).

### Setup Script Alignment

* Added or moved all corresponding configuration blocks into `setup-system.sh` and `setup-obsidian-git.sh` so new tests pass out-of-the-box.

---

## v0.2.1 – Usability Improvements (2025-06-28)

### Logging Enhancements

* `--log[=FILE]` / `-l`: force writing a full log on every run.
* Sensible defaults: logs written to `logs/` with timestamped filenames.

### User Setup Enhancements

* Configures **both** `git` and `obsidian` users (instead of only `git`).
* Blank initial passwords assigned for both users (can be pulled from a secrets file).
* Fixed the bug in `setup-obsidian-git.sh` that this change introduced.

### Refactor and Sync Code

* Moved missing code blocks from `setup-all.sh` into `setup-obsidian-git.sh`.
* Mirrored those changes in the corresponding test scripts for consistency.

---

## v0.2 – Modular Setup and Test Suite (2025-06-27)

### Architecture Overhaul

* Split monolithic scripts into modular components:

  * `setup-system.sh`, `setup-obsidian-git.sh`, `setup-github.sh`
  * `test-system.sh`, `test-obsidian-git.sh`, `test-github.sh`

### Wrapper Script Additions

* Introduced `setup-all.sh` and `test-all.sh` for full automation.

### General Improvements

* Preserved environment variable support across all layers.
* Deployment now safer — deploy key no longer must be committed.
* Simplified maintenance and clearer separation of concerns.

---

## v0.1.1 – Strict Hostname Format & Test Suite Enhancements (2025-06-24)

### Highlights

* Obsoletes v0.1: all improvements consolidated into 0.1.1.

### Format Validation Additions

* Added strict format validation for `inet <IP> <NETMASK>` and `!route add default <GATEWAY>` lines in `hostname.${INTERFACE}`.
* Anchored regex checks to prevent use of the old `netmask` keyword.

### Test Suite Enhancements

* Retained all existing tests for:

  * User setup and login shells
  * `doas.conf` policy
  * Static networking and DNS
  * SSH hardening
  * Git installation and config
  * Repo structure and `safe.directory` flags

---

## v0.1 – Initial Public Release (2025-06-23)

### Scripts Included

* `openbsd_server_rebuild_public_v0.1.sh`:

  * Sets up static networking, hardened SSH, users, Git, and bare repo.
  * Applies `safe.directory` flags and configures `doas`.

* `test_openbsd_setup_public_v0.1.sh`:

  * TAP-compatible test suite validating the above setup.
  * Covers users, perms, `doas`, networking, DNS, SSH, Git, and repo structure.

### Key Features

* Self-contained, repeatable tests
* Non-destructive, read-only validation
* Fully functional Git-backed vault hosting setup

---



