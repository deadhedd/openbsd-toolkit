# obsidian-git-host

## Purpose
Creates users, SSH rules and a shared bare Git repository so multiple accounts can sync an Obsidian vault.

## Prerequisites
- Run as root on OpenBSD 7.4+
- `config/secrets.env` populated
- Network access to the Git server

## Key variables
| Variable | Description |
| --- | --- |
| `OBS_USER` | Local Obsidian user |
| `GIT_USER` | Service account used for pushes |
| `VAULT` | Vault name used for repository paths |
| `GIT_SERVER` | Hostname or IP for known_hosts entry |

## Setup
```sh
cd modules/obsidian-git-host
sh setup.sh [--debug]
```

## Testing
```sh
sh test.sh [--debug]
```
