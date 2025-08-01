# github

## Purpose
Installs a deploy key for GitHub and clones a remote repository for use with Obsidian.

## Prerequisites
- Run as root on OpenBSD 7.4+
- `config/secrets.env` with required values
- `config/deploy_key` containing the private deploy key

## Key variables
| Variable | Description |
| --- | --- |
| `LOCAL_DIR` | Destination path for the local clone |
| `GITHUB_REPO` | GitHub repository URL |

## Setup
```sh
cd modules/github
sh setup.sh [--debug]
```

## Testing
```sh
sh test.sh [--debug]
```
