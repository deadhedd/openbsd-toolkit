# openbsd-server

A collection of scripts to configure and validate an OpenBSD server for hosting a Git-backed Obsidian vault.

---

## Scripts

* **openbsd\_server\_rebuild\_public\_v0.1.1.sh**
  Automates setup of a fresh OpenBSD server with the revised hostname file format to ensure persistent network configuration across reboots.

* **test\_openbsd\_setup\_public\_v0.1.1.sh**
  A self-contained TAP-compatible test suite that checks:

  * User account setup & shells
  * File permissions & doas policy
  * Static network config & DNS, with strict format validation:

    * Asserts `hostname.${INTERFACE}` first line is exactly `inet <IP> <NETMASK>`
    * Asserts second line is exactly `!route add default <GATEWAY>`
    * Anchored regex checks to prevent forbidden keywords
  * SSH hardening
  * Git installation & push access
  * Bare-repo structure & safe-directory flags

---

## Usage

### Run the tests

```sh
sh test_openbsd_setup_public_v0.1.1.sh
```

You can override defaults via environment variables:

```sh
REG_USER=obsidian \
GIT_USER=git \
VAULT=myvault \
INTERFACE=em0 \
STATIC_IP=192.0.2.10 \
NETMASK=255.255.255.0 \
GATEWAY=192.0.2.1 \
sh test_openbsd_setup_public_v0.1.1.sh
```

### Run the setup

```sh
sh openbsd_server_rebuild_public_v0.1.1.sh
```

### Releases & Tags

Tags are used for versioned snapshots:

```sh
git push origin --tags
```

Visit the Releases page on GitHub to download.

---

## Changelog

### v0.1 – Initial release

* Setup and validation suite for OpenBSD server configuration (network, users, SSH, Git, etc.)

### v0.1.1 – Test enhancements (2025-06-23)

* Obsoletes v0.1
* Added strict format validation for `inet <IP> <NETMASK>` and `!route add default <GATEWAY>` lines in `hostname.${INTERFACE}`
* Anchored regex checks to prevent use of the old `netmask` keyword
* Retained all core validation tests from v0.1

---

## License

MIT OR 0BSD — see the LICENSE file.
