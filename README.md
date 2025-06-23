# openbsd-server

A collection of scripts to configure and validate an OpenBSD server for hosting a Git-backed Obsidian vault.

---

## Scripts

### v0.1

- **openbsd_server_rebuild_public_v0.1.sh**  
  Automates setup of a fresh OpenBSD server so that it passes our validation tests.

- **test_openbsd_setup_public_v0.1.sh**  
  A self-contained TAP-compatible test suite that checks:
  - User account setup & shells  
  - File permissions & doas policy  
  - Static network config & DNS  
  - SSH hardening  
  - Git installation & push access  
  - Bare-repo structure & safe directory flags  

### v0.1.1 (test enhancements)

- **test_openbsd_setup_public_v0.1.1.sh**  
  Prep for next iteration—adds additional checks and refactors existing tests.

---

## Usage

### Run the tests

```sh
sh test_openbsd_setup_public_v0.1.sh
```

Or (for the upcoming iteration):

```sh
sh test_openbsd_setup_public_v0.1.1.sh
```

You can override any default via environment variables:

```
REG_USER=obsidian \
GIT_USER=git \
VAULT=myvault \
INTERFACE=em0 \
STATIC_IP=192.0.2.10 \
sh test_openbsd_setup_public_v0.1.sh
```

Run the setup

```
sh openbsd_server_rebuild_public_v0.1.sh
```

Releases & Tags

I tag each public version so you can grab a ZIP directly:

    v0.1 – passing setup and test suite

    v0.1.1 – next-iteration test enhancements

If you haven’t already:

```sh
git push origin --tags
```

And you can see our formal Releases page on GitHub.
License

MIT OR 0BSD — see the LICENSE file.
