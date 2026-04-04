#!/usr/bin/env bash
set -euo pipefail

DEVENV_TASK_INPUT='{"host":""}'
if DEVENV_TASK_INPUT="$DEVENV_TASK_INPUT" ./modules/deployment/scripts/update-system.sh 2>/dev/null; then
  echo "expected failure for empty host"
  exit 1
fi

DEVENV_TASK_INPUT='{"host":"ssdinarch-0","validate_only":true}'
if ! DEVENV_TASK_INPUT="$DEVENV_TASK_INPUT" ./modules/deployment/scripts/update-system.sh >/dev/null; then
  echo "expected success for validate_only host"
  exit 1
fi

DEVENV_TASK_INPUT='{"host":"ssdinarch-0"}'
if DEVENV_TASK_INPUT="$DEVENV_TASK_INPUT" ./modules/deployment/scripts/update-system.sh 2>/dev/null; then
  echo "expected non-validate update to fail until in-machine implementation exists"
  exit 1
fi

echo "update-system basic test passed"
