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

# Copy config templates if needed
cd "$DEST"
if [ ! -f config/secrets.env ] && [ -f config/secrets.env.example ]; then
  cp config/secrets.env.example config/secrets.env
  echo "Copied config/secrets.env.example -> config/secrets.env"
fi

echo

echo "SUCCESS! Files available at: $DEST"
echo "Next steps:"
echo "   - Edit config/secrets.env to match your environment"
echo "   - If desired, modify config/enabled_modules.conf to control which modules install"
echo "   - Then run: install_modules.sh"
