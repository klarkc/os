#!/usr/bin/env bash
set -euo pipefail

FAIL=0

for test in $(find modules -name '*.test.sh' | sort); do
  echo "[TEST] $test"
  if ! bash "$test"; then
    echo "[FAIL] $test"
    FAIL=1
  else
    echo "[OK] $test"
  fi
  echo
done

exit $FAIL
