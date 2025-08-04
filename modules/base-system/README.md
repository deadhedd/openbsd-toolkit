# base-system

## Purpose
Configures hostname, networking, SSH hardening, root SSH authorized keys, and root shell history on a fresh OpenBSD server.

## Prerequisites
- Run as root on OpenBSD 7.4+
- `config/secrets.env` populated and readable by the scripts

## Key variables
| Variable | Description |
| --- | --- |
| `INTERFACE` | Network interface to configure (e.g. `em0`) |
| `GIT_SERVER` | Server IP address |
| `NETMASK` | Network mask |
| `GATEWAY` | Default gateway |
| `DNS1`, `DNS2` | Resolver addresses |
| `ROOT_SSH_PUBLIC_KEY_FILES` | Space-separated list of root SSH public key filenames |

## Setup
```sh
cd modules/base-system
sh setup.sh [--debug]
```

## Testing
```sh
sh test.sh [--debug]
```
