# obsidian-git-client

## Purpose
Checks that a workstation's Obsidian vault is a Git repository.

## Prerequisites
- Client with Git
- `config/secrets.env` filled with connection details
- Vault repository cloned locally at `$HOME/$VAULT`

## Key variables
| Variable | Description |
| --- | --- |
| `VAULT` | Vault/repository name |

## Setup
1. Copy `config/secrets.env.example` to `config/secrets.env` and edit the values.
2. Clone the vault to `$HOME/$VAULT`.

## Testing
```sh
cd modules/obsidian-git-client
sh test.sh [--log[=FILE]]
```
