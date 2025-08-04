# github

## Purpose
Installs SSH keys for GitHub and clones a remote repository for use with Obsidian.

## Prerequisites
- Run as root on OpenBSD 7.4+
- `config/secrets.env` with required values
- SSH key files referenced by `GITHUB_SSH_PRIVATE_KEY_FILE` and `GITHUB_SSH_PUBLIC_KEY_FILE` located in `config/`

## Key variables
| Variable | Description |
| --- | --- |
| `LOCAL_DIR` | Destination path for the local clone |
| `GITHUB_REPO` | GitHub repository URL |
| `GITHUB_SSH_PRIVATE_KEY_FILE` | Private key filename in `config/` |
| `GITHUB_SSH_PUBLIC_KEY_FILE` | Public key filename in `config/` |

## Setup
```sh
cd modules/github
sh setup.sh [--debug]
```

## Testing
```sh
sh test.sh [--debug]
```
