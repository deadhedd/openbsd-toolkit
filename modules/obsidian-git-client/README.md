# obsidian-git-client

## Purpose
Checks that a workstation can pull and push an Obsidian vault over SSH.

## Prerequisites
- Client with Git, ssh-agent and access to the remote server
- `config/secrets.env` filled with connection details
- Vault repository cloned locally at `$HOME/$VAULT`

## Key variables
| Variable | Description |
| --- | --- |
| `GIT_USER` | Remote git service account |
| `OBS_USER` | Remote Obsidian account |
| `VAULT` | Vault/repository name |
| `SERVER` | Hostname or IP of the git server |

## Setup
1. Copy `config/secrets.env.example` to `config/secrets.env` and edit the values.
2. Start `ssh-agent` and add your private key.
3. Clone the remote vault to `$HOME/$VAULT`.

## Testing
```sh
cd modules/obsidian-git-client
sh test.sh [--log[=FILE]]
```
