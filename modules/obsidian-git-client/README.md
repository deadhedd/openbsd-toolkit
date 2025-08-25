# obsidian-git-client

## Purpose
Checks that a workstation can pull and push an Obsidian vault over SSH.

## Prerequisites
- Client with Git, ssh-agent and access to the remote server
- `config/secrets.env` filled with connection details
- Vault repository cloned locally at `$HOME/$CLIENT_VAULT`

## Key variables
| Variable | Description |
| --- | --- |
| `GIT_USER` | Remote git service account |
| `OBS_USER` | Remote Obsidian account |
| `VAULT` | Vault/repository name |
| `CLIENT_VAULT` | Local vault directory name |
| `GIT_SERVER` | Hostname or IP of the git server |

## Setup
Run the setup script with the required options:

```sh
cd modules/obsidian-git-client
sudo bash setup.sh --vault /path/to/Vault --owner USER --remote-url git@server:/path/to/vault.git [options]
```

### Options
| Option | Description | Default |
| --- | --- | --- |
| `--vault PATH` | Vault directory (created if missing) | required |
| `--owner USER` | Local user that owns the vault | required |
| `--remote-url URL` | Git remote for the vault | required |
| `--branch NAME` | Branch name to use if initializing | `main` |
| `--ssh-host HOST` | SSH host for known_hosts | derived from remote |
| `--ssh-port PORT` | SSH port | `22` |
| `--no-accept-hostkey` | Skip ssh-keyscan/known_hosts pinning | host key pinned |
| `--ssh-key-path PATH` | SSH private key path | `/home/<owner>/.ssh/id_ed25519` |
| `--ssh-generate` | Generate key at the path if missing | off |
| `--ssh-copy-id` | Copy the public key to the remote | off |
| `--push-initial` | Seed a first commit and push if repo is empty | off |
| `--initial-sync MODE` | First sync policy: `remote-wins`, `local-wins`, `merge`, or `none` | `none` |

## Testing
```sh
cd modules/obsidian-git-client
sh test.sh [--log[=FILE]]
```
