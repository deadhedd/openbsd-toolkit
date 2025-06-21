# OpenBSD Server Setup Test Script

This script verifies that an OpenBSD server has been correctly configured to host a Git-synced Obsidian vault. It performs 19 POSIX-compliant checks across user accounts, shell configuration, networking, Git setup, and login shell profiles.

## Features

- 🔒 Verifies safe user shells and doas permissions
- 🌐 Confirms correct network and DNS configuration
- 🔐 Checks SSHD security settings
- 🧠 Ensures Git repos and working clones are correctly owned and configured
- 📦 Fully POSIX-compliant — runs under `/bin/sh`
- ✅ TAP-like output for potential CI integration

## Requirements

- OpenBSD (tested with 7.x)
- Git installed via `pkg_add git`

## Usage

```sh
sh test_openbsd_setup.sh
```

You can override default values using environment variables:

```sh
REG_USER=myuser GIT_USER=mygit VAULT=myvault sh test_openbsd_setup.sh
```

## Environment Variables

|Variable|Default|Description|
|---|---|---|
|`REG_USER`|`obsidian`|Regular user who owns the working copy|
|`GIT_USER`|`git`|Git-only user who owns the bare repo|
|`VAULT`|`Main`|Vault name|
|`INTERFACE`|`em0`|Network interface|
|`STATIC_IP`|`192.0.2.10`|Expected IP address (RFC 5737 test range)|
|`NETMASK`|`255.255.255.0`|Netmask|
|`GATEWAY`|`192.0.2.1`|Default gateway|
|`DNS1`|`1.1.1.1`|Primary DNS|
|`DNS2`|`8.8.8.8`|Secondary DNS|

## License

MIT — see `LICENSE` file.