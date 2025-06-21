# test_openbsd_setup.sh

A self-contained TAP-compatible test script that verifies whether an OpenBSD server has been correctly configured to host a Git-backed Obsidian vault.

This script is safe to run repeatedly. It performs **non-destructive**, **read-only checks** covering:

- User account setup and shell assignment
- File permissions and `doas` policy
- Static network configuration and DNS
- SSH hardening settings
- Git install and push access
- Bare repo structure and safe directory flags

> ⚠️ Currently versioned as `v0.1` — an early public release. Contributions, issues, and suggestions are welcome.

---

## 🔧 Usage

```sh
sh test_openbsd_setup.sh
````

### Optional: Override defaults via environment variables

```sh
REG_USER=obsidian \
GIT_USER=git \
VAULT=myvault \
INTERFACE=em0 \
STATIC_IP=192.0.2.10 \
sh test_openbsd_setup.sh
```

---

## 📋 Output Format

This script uses the [TAP](https://testanything.org/) (Test Anything Protocol) format, making it easy to use in pipelines or automated test harnesses.

Sample output:

```
ok 1 - user 'obsidian' exists with ksh shell
ok 2 - user 'git' exists with git-shell
...
not ok 14 - sshd_config allows only obsidian,git
...
1..27
2 of 27 tests failed.
```

---

## 📁 Directory Structure Expectations

- Bare repo: `/home/git/vaults/vault.git`
    
- Working clone: `/home/obsidian/vaults/vault`
    
- Setup script lives at: `/root/openbsd-server/`
    

---

## 🪪 License

MIT OR 0BSD — see LICENSE
