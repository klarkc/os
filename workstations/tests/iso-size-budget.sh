#!/usr/bin/env bash
# ISO size regression for the disposable lpklarkc RDP appliance.
set -euo pipefail

if [[ "${1:-}" == "--self-test" ]]; then
  fixture="$(mktemp)"
  trap 'rm -f -- "$fixture"' EXIT
  truncate -s 1048576 "$fixture"
  MAX_ISO_MIB=1 bash "$0" "$fixture" >/dev/null
  truncate -s 1048577 "$fixture"
  if MAX_ISO_MIB=1 bash "$0" "$fixture" >/dev/null 2>&1; then
    echo "FAIL: limit accepted a 1 MiB + 1 byte ISO" >&2
    exit 1
  fi
  echo "PASS: ISO size boundary regression"
  exit 0
fi

file="${1:?Usage: iso-size-budget.sh path/to/lpklarkc-x86_64.iso}"
[[ -f "$file" ]] || { echo "ISO missing: $file" >&2; exit 2; }
max_mib="${MAX_ISO_MIB:-1536}"
[[ "$max_mib" =~ ^[1-9][0-9]*$ ]] || {
  echo "MAX_ISO_MIB must be a positive integer" >&2
  exit 2
}
bytes="$(stat -c %s -- "$file")"
max_bytes="$((max_mib * 1024 * 1024))"
echo "lpklarkc ISO: $bytes bytes ($(( (bytes + 1048575) / 1048576 )) MiB rounded up); budget $max_bytes bytes ($max_mib MiB)"
if (( bytes == 0 || bytes > max_bytes )); then
  echo "FAIL: lpklarkc ISO too large or empty" >&2
  exit 1
fi
echo "PASS: lpklarkc ISO size budget"
