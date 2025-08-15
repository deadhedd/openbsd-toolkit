# obsidian-git-host

## Purpose
Creates users and a shared bare Git repository so multiple accounts can sync an Obsidian vault. Service accounts have SSH access restricted to `git-shell`.

## Prerequisites
- Run as root on OpenBSD 7.4+
- `config/secrets.env` populated

## Key variables
| Variable | Description |
| --- | --- |
| `OBS_USER` | Local Obsidian user |
| `GIT_USER` | Service account used for pushes |
| `VAULT` | Vault name used for repository paths |
| `GIT_SERVER` | Hostname or IP used for SSH known_hosts |

## Setup
```sh
cd modules/obsidian-git-host
sh setup.sh [--debug]
```

## Testing
```sh
sh test.sh [--debug]
```
