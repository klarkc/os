#!/usr/bin/env bash
# Intentionally retired: GCE stop/start loses RAM, live processes and XMonad.
# This historical CI hook is left only to fail closed when invoked directly.
# Replace it with a separately approved instances.suspend/resume E2E test on
# an equivalent disposable VM, proving the same boot_id, PIDs and RAM marker.
set -euo pipefail
echo "BLOCKED: stop/start is prohibited for session-preserving wsklarkc tests" >&2
exit 2
