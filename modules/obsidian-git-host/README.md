# obsidian-git-host

## Purpose
Creates users and a shared bare Git repository so multiple accounts can sync an Obsidian vault. Service accounts do not have SSH access.

## Prerequisites
- Run as root on OpenBSD 7.4+
- `config/secrets.env` populated

## Key variables
| Variable | Description |
| --- | --- |
| `OBS_USER` | Local Obsidian user |
| `GIT_USER` | Service account used for pushes |
| `VAULT` | Vault name used for repository paths |

## Setup
```sh
cd modules/obsidian-git-host
sh setup.sh [--debug]
```

## Testing
```sh
sh test.sh [--debug]
```
