# openbsd-server

A collection of modular scripts to configure and validate an OpenBSD server for hosting a Git-backed Obsidian vault, with support for GitHub deploy key integration.

---

## Scripts Overview

### Setup Scripts

| Script                      | Purpose                                              |
|-----------------------------|------------------------------------------------------|
| `setup_system.sh`           | Installs packages, creates users, sets up networking and doas, hardens SSH, configures user profiles. |
| `setup_obsidian_git.sh`     | Initializes the Git bare repo and working copy for Obsidian vault syncing. |
| `setup_github.sh`           | Installs deploy key and bootstraps the GitHub repo clone for ongoing configuration management. |
| `setup_all.sh`              | Runs all of the above in sequence. |

### Test Suites

| Script                      | Validates                                             |
|-----------------------------|-------------------------------------------------------|
| `test_system.sh`            | User setup, file permissions, doas, network, DNS, SSH security. |
| `test_obsidian_git.sh`      | Git bare repo structure, safe.directory flags, post-receive hook. |
| `test_github.sh`            | Deploy key presence and permission, GitHub in known_hosts. |
| `test_all.sh`               | Runs all of the above in sequence. |

---

## Usage

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
sh test_all.sh
```

Same environment variables apply.

---

## Releases & Tags

Use version tags to snapshot working configurations:

```sh
git tag -a v0.2.0 -m "Modular setup and test scripts"
git push origin --tags
```

---

## Changelog

### v0.2.0 – Modularization (2025-06-26)

* **Split monolithic setup/test scripts** into:

  * `setup_system.sh`
  * `setup_obsidian_git.sh`
  * `setup_github.sh`
  * `test_system.sh`
  * `test_obsidian_git.sh`
  * `test_github.sh`
* Added `setup_all.sh` and `test_all.sh` for convenience

### v0.1.1 – Test Enhancements (2025-06-23)

* Added strict validation for network config files
* Anchored regex to prevent deprecated `netmask` lines
* Retained all core tests from v0.1

### v0.1 – Initial Release

* Setup and validation for OpenBSD server configuration (users, SSH, network, Git)

---

## License

MIT OR 0BSD — see the LICENSE file.

```
