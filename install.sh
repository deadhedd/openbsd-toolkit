#!/bin/sh
# install.sh — simple installer for the OpenBSD Toolkit
# Usage: sh install.sh [install-directory]

set -e

REPO_URL="https://github.com/deadhedd/openbsd-toolkit"
DEST="$HOME/openbsd-toolkit"

# Allow custom install dir
if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [install-directory]"
  exit 1
elif [ "$#" -eq 1 ]; then
  DEST="$1"
fi

echo "📦 Installing OpenBSD Toolkit"
echo "🔗 Repo:     $REPO_URL"
echo "📁 Dest Dir: $DEST"
echo

# prereq: git
if ! command -v git >/dev/null 2>&1; then
  echo "❌ error: 'git' is not installed. Install with: pkg_add git"
  exit 1
fi

if [ -d "$DEST" ]; then
  echo "❌ error: destination '$DEST' already exists."
  echo "   Remove or rename it before retrying."
  exit 1
fi

git clone --depth=1 "$REPO_URL" "$DEST"

# Run setup if present
if [ -x "$DEST/scripts/setup.sh" ]; then
  echo
  echo "🚀 Running setup script..."
  sh "$DEST/scripts/setup.sh" --debug
else
  echo
  echo "⚠️  setup.sh not found or not executable. Skipping setup."
fi

echo
echo "✅ OpenBSD Toolkit installed at: $DEST"
