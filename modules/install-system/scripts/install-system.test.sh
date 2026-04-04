#!/usr/bin/env bash
set -euo pipefail

if ./modules/install-system/scripts/install-system.sh "" 2>/dev/null; then
  echo "expected failure for empty host"
  exit 1
fi

echo "install-system basic test passed"
