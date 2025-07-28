#!/bin/sh
#
# setup.sh - GitHub deploy key & repo bootstrap (github module)
# Usage: ./setup.sh [--debug[=FILE]] [-h]

##############################################################################
# 0) Resolve Paths
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export PROJECT_ROOT

##############################################################################
# 1) Help & banned flags prescan
##############################################################################

show_help() {
  cat <<-EOF
  Usage: $(basename "$0") [options]

  Description:
    Configure GitHub deploy key and initialize bare repo

  Options:
    -h, --help        Show this help message and exit
    -d, --debug       Enable debug/xtrace and write a log file
EOF
}
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      show_help
      exit 0
      ;;
    -l|--log|-l=*|--log=*)
      printf '%s\n' "This script no longer supports --log. Did you mean --debug?" >&2
      exit 2
      ;;
  esac
done

##############################################################################
# 2) Logging init
##############################################################################

# shellcheck source=logs/logging.sh
. "$PROJECT_ROOT/logs/logging.sh"
parse_logging_flags "$@"
eval "set -- $REMAINING_ARGS"

module_name="$(basename "$SCRIPT_DIR")"
if [ "$DEBUG_MODE" -eq 1 ]; then
  set -vx  # enable xtrace
  init_logging "setup-$module_name"
fi

##############################################################################
# 3) Inputs (secrets & constants) + validation
##############################################################################

. "$PROJECT_ROOT/config/load_secrets.sh"
DEPLOY_KEY="$PROJECT_ROOT/config/deploy_key"

[ -f "$DEPLOY_KEY" ] || { echo "ERROR: deploy_key not found at $DEPLOY_KEY" >&2; exit 1; }

##############################################################################
# 4) SSH setup (keys & known_hosts)
##############################################################################

mkdir -p /root/.ssh
cp "$DEPLOY_KEY" /root/.ssh/id_ed25519
chmod 600 /root/.ssh/id_ed25519

ssh-keyscan github.com >> /root/.ssh/known_hosts

: "LOCAL_DIR=$LOCAL_DIR"       # ensure variable is set
: "GITHUB_REPO=$GITHUB_REPO"   # ensure variable is set

[ -n "$LOCAL_DIR" ]   || { echo "ERROR: LOCAL_DIR not set" >&2; exit 1; }
[ -n "$GITHUB_REPO" ] || { echo "ERROR: GITHUB_REPO not set" >&2; exit 1; }

##############################################################################
# 5) Repo bootstrap
##############################################################################

git clone "$GITHUB_REPO" "$LOCAL_DIR"

echo "github: GitHub configuration complete!"
