#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo 'ERROR: not in a Git checkout' >&2; exit 2; }
bash "$root/workstations/tests/repository-file-policy.sh" --hook
if ! command -v gitleaks >/dev/null 2>&1; then
  echo "ERROR: gitleaks missing. Use the versioned nix develop shell." >&2
  exit 1
fi
# This is intentionally a hard security check of staged content.
# The file-extension check above is advisory only.
gitleaks protect --staged --redact --no-banner
