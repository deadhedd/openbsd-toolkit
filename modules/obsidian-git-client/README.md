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
After populating the `Obsidian Git Client` and `SSH` sections in `config/secrets.env`, run:

```sh
cd modules/obsidian-git-client
sudo bash setup.sh [options]
```

The script reads default values from `config/secrets.env`. Command-line options can
still override any of these settings:

### Options
| Option | Description | Default |
| --- | --- | --- |
| `--vault PATH` | Vault directory (created if missing) | `/home/$CLIENT_OWNER/$CLIENT_VAULT` |
| `--owner USER` | Local user that owns the vault | `$CLIENT_OWNER` |
| `--remote-url URL` | Git remote for the vault | `$CLIENT_REMOTE_URL` |
| `--branch NAME` | Branch name to use if initializing | `$CLIENT_BRANCH` or `main` |
| `--ssh-host HOST` | SSH host for known_hosts | `$CLIENT_SSH_HOST` or derived from remote |
| `--ssh-port PORT` | SSH port | `$CLIENT_SSH_PORT` or `22` |
| `--no-accept-hostkey` | Skip ssh-keyscan/known_hosts pinning | use secrets or host key pinned |
| `--ssh-key-path PATH` | SSH private key path | `$CLIENT_SSH_KEY_PATH` or key from SSH module (`$SSH_KEY_DIR/$SSH_PRIVATE_KEY_DEFAULT`) |
| `--ssh-generate` | Generate key at the path if missing | `$CLIENT_SSH_GENERATE` or off |
| `--ssh-copy-id` | Copy the public key to the remote | `$CLIENT_SSH_COPY_ID` or off |
| `--push-initial` | Seed a first commit and push if repo is empty | `$CLIENT_PUSH_INITIAL` or off |
| `--initial-sync MODE` | First sync policy: `remote-wins`, `local-wins`, `merge`, or `none` | `$CLIENT_INITIAL_SYNC` or `none` |
## Testing
```sh
cd modules/obsidian-git-client
sh test.sh [--log[=FILE]]
```
