# obsidian-git-client

## Purpose
Installs Obsidian, side-loads the [obsidian-git](https://github.com/denolehov/obsidian-git)
plugin, and wires up SSH/Git so a workstation can pull and push a vault over
SSH.

## Prerequisites
- Client with Git, ssh-agent and access to the remote server
- `config/secrets.env` filled with connection details
- Vault repository cloned locally at `$CLIENT_VAULT_PATH` (defaults to `/home/$CLIENT_OWNER/$CLIENT_VAULT`)

## Key variables
| Variable | Description |
| --- | --- |
| `GIT_USER` | Remote git service account |
| `OBS_USER` | Remote Obsidian account |
| `VAULT` | Vault/repository name |
| `CLIENT_VAULT_PATH` | Local vault directory path (optional) |
| `CLIENT_VAULT` | Local vault directory name (used if `CLIENT_VAULT_PATH` unset) |
| `GIT_SERVER` | Hostname or IP of the git server |

## Features
- Installs the Obsidian desktop app on Debian/Ubuntu systems.
- Side-loads the obsidian-git plugin into the configured vault.
- Configures SSH known_hosts, keys, and agent for the vault owner.
- Sets the Git remote/branch and optionally seeds an initial commit.
- Can auto-generate SSH keys and copy them to the remote server.

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
| `--vault PATH` | Vault directory (created if missing) | `$CLIENT_VAULT_PATH` or `/home/$CLIENT_OWNER/$CLIENT_VAULT` |
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
| `--initial-sync MODE` | First sync policy: `remote-wins`, `local-wins`, `merge`, or `none` | `$CLIENT_INITIAL_SYNC` or `none` 

#### Example
```sh
sudo bash setup.sh \
  --vault "$HOME/SecondBrain" \
  --owner "$USER" \
  --remote-url git@example.com:/home/git/vaults/SecondBrain.git \
  --ssh-generate --ssh-copy-id --push-initial --initial-sync remote-wins
```
## Testing
```sh
cd modules/obsidian-git-client
sh test.sh [--log[=FILE]]
```

The test suite performs TAP-style checks to confirm the plugin is installed,
SSH keys/known_hosts are in place, and the vault's Git remote is configured
correctly.
