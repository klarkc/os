#!/usr/bin/env bash
set -euo pipefail

DEVENV_TASK_INPUT='{"host":""}'
if DEVENV_TASK_INPUT="$DEVENV_TASK_INPUT" ./modules/deployment/scripts/install-system.sh 2>/dev/null; then
  echo "expected failure for empty host"
  exit 1
fi

DEVENV_TASK_INPUT='{"host":"ssdinarch-0","validate_only":true}'
if ! DEVENV_TASK_INPUT="$DEVENV_TASK_INPUT" ./modules/deployment/scripts/install-system.sh >/dev/null; then
  echo "expected success for validate_only host"
  exit 1
fi

DEVENV_TASK_INPUT='{"host":"ssdinarch-0","target_ssh":"root@example","target_disk":"/dev/vda","validate_only":true}'
if DEVENV_TASK_INPUT="$DEVENV_TASK_INPUT" ./modules/deployment/scripts/install-system.sh 2>/dev/null; then
  echo "expected failure for multiple target kinds"
  exit 1
fi

echo "install-system basic test passed"
