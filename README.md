# 🛠️ OpenBSD Toolkit

Modular shell scripts for automating system setup and tooling on OpenBSD, starting with a fully working Obsidian Git host. Built with security, maintainability, and automation in mind — with future plans to expand into general-purpose OpenBSD tools.

---

## 🚀 Quick Start

The fastest way to get started is to run the installer directly from GitHub Pages:

```sh
ftp -o - https://deadhedd.github.io/openbsd-toolkit/install.sh | sh
```

Alternatively, clone the repo manually:

```sh
git clone https://github.com/deadhedd/openbsd-toolkit
cd openbsd-toolkit
sh install_modules.sh
```

Use `--help` for options:

```sh
sh install_modules.sh --help
```

Then validate your setup:

```sh
sh test_all.sh
```

---

## 📦 Requirements

* OpenBSD 7.4+
* Obsidian with the Git plugin (on your client)
* Optional: SSH keys, GitHub repo for vault prefill

---

## 🧠 Project Overview

This toolkit currently includes:

* A base-system setup module for configuring OpenBSD itself (users, doas, network, etc.)
* A Git bare repo module to host an Obsidian-compatible vault with auto-deploy
* A minimal GitHub module for immediate push capability after setup

All modules are modular and extensible. The long-term vision includes additional OpenBSD automation tools for broader system management.

---

## 🧱 Architecture

Directory layout:

```
openbsd-toolkit/
├── config/           # Secrets and module selection
├── logs/             # Auto-created during runs
├── modules/          # One folder per module
│   └── <module>/     
│       ├── setup.sh  # Configures that module
│       └── test.sh   # Verifies it works
├── install_modules.sh  # Installs selected modules
└── test_all.sh          # Runs all tests
```

Modules are declared in `config/enabled_modules.conf`. Each module’s `setup.sh` and `test.sh` can be run independently or as part of a full stack install/test.

---

## 🔧 Module Guide

| Module              | Description                                                |
| ------------------- | ---------------------------------------------------------- |
| `base-system`       | Sets up OpenBSD base config (e.g. `doas.conf`, networking) |
| `obsidian-git-host` | Creates the Git bare repo, vault, and deployment hook      |
| `github` (optional) | Enables immediate GitHub push support for new setups       |

Each module:

* Can be run independently
* Can be toggled via `enabled_modules.conf`
* Supports logging flags and will generate a separate log file when run on its own
* When run via `install_modules.sh` or `test_all.sh`, logs are combined into a single output file

---

## 🧪 Testing

Test a single module:

```sh
sh modules/<module>/test.sh
```

Run full system tests:

```sh
sh test_all.sh
```

Logs are saved to the `logs/` directory. By default, logs are only saved when a test fails.

Use `--debug[=FILE]` to enable verbose tracing and optionally direct output to a specific log file.

Use `--log[=FILE]` to force a log file to be written even when all tests pass (only supported by test scripts).

### Simplified logging helpers

Scripts source `logs/logging.sh` and invoke one of these convenience functions:

```sh
. "$PROJECT_ROOT/logs/logging.sh"
start_logging "$0" "$@"            # for test scripts
# or
start_logging_if_debug "setup-my-module" "$@"  # for setup scripts
```

`start_logging` automatically sets up logging, enables debug tracing when
`--debug` is provided, and registers `finalize_logging` on exit.

---

## 🛡️ Security Notes

* SSH keys and passwords are defined in `config/secrets.env`
* The `--debug` option will include secrets and other sensitive data in the logs; take care when sharing debug output
* All Git hooks run as limited users with appropriate `doas.conf` constraints

---

## 📜 License

BSD 2-Clause License. See [`LICENSE`](LICENSE) for full details.

