#!/bin/sh
#
# test_all.sh - Run all three test suites and report overall result
# Usage: ./test_all.sh
set -u

# Locate this script’s directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

EXIT_CODE=0

for suite in \
  test_system.sh \
  test_obsidian_git.sh \
  test_github.sh
do
  echo "=== Running $suite ==="
  sh "$SCRIPT_DIR/$suite" || EXIT_CODE=1
  echo ""
done

if [ "$EXIT_CODE" -eq 0 ]; then
  echo "✅ All test suites passed."
else
  echo "❌ One or more test suites failed."
fi

exit $EXIT_CODE
