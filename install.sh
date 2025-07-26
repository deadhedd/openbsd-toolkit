#!/bin/sh
# install.sh — Simple clone installer for the OpenBSD Toolkit
# Usage: sh install.sh [DEST]

set -e

REPO_URL="https://github.com/deadhedd/openbsd-toolkit"
# Default destination: ~/openbsd-toolkit or first argument
DEST="${1:-$HOME/openbsd-toolkit}"

# Banner
echo "Cloning OpenBSD Toolkit"
echo "Repo:     $REPO_URL"
echo "Dest Dir: $DEST"
echo

# Clone repository (shallow)
git clone --depth=1 "$REPO_URL" "$DEST"

echo
echo "SUCCESS! Files available at: $DEST"
echo "Next: cd $DEST and run scripts/setup.sh as needed."
