#!/bin/sh
#
# setup_all.sh - Run all three setup scripts in sequence
# Usage: ./setup_all.sh
set -e

# Locate this script’s directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "👉 Running system setup…"
sh "$SCRIPT_DIR/setup_system.sh"

echo "👉 Running Obsidian-sync setup…"
sh "$SCRIPT_DIR/setup_obsidian.sh"

echo "👉 Running GitHub-config setup…"
sh "$SCRIPT_DIR/setup_github.sh"

echo ""
echo "✅ All setup scripts completed successfully."
