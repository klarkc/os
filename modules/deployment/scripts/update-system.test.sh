#!/usr/bin/env bash
set -euo pipefail

DEVENV_TASK_INPUT='{"host":"unknown-host","validate_only":true}'
if DEVENV_TASK_INPUT="$DEVENV_TASK_INPUT" update-system --repo-root "$PWD" 2>/dev/null; then
  echo "expected failure for unknown host"
  exit 1
fi

DEVENV_TASK_INPUT='{"host":"ssdinarch-0","validate_only":true}'
if ! DEVENV_TASK_INPUT="$DEVENV_TASK_INPUT" update-system --repo-root "$PWD" >/dev/null; then
  echo "expected success for validate_only host"
  exit 1
fi

DEVENV_TASK_INPUT='{"host":"ssdinarch-0"}'
if DEVENV_TASK_INPUT="$DEVENV_TASK_INPUT" update-system --repo-root "$PWD" 2>/dev/null; then
  echo "expected non-validate update to fail without root privileges"
  exit 1
fi

echo "update-system basic test passed"
