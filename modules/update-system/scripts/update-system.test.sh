#!/usr/bin/env bash
set -euo pipefail

if ./modules/update-system/scripts/update-system.sh "" 2>/dev/null; then
  echo "expected failure for empty host"
  exit 1
fi

echo "update-system basic test passed"
