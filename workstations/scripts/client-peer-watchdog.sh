#!/usr/bin/env bash
# Independent read-only watchdog while FreeRDP blocks the kiosk's console.
# Only a confirmed final server state permits an ordinary Dell shutdown.
set -euo pipefail
IAP="${LPKLARKC_IAP_TOOL:-/run/current-system/sw/bin/lpklarkc-iap}"
SUDO="${LPKLARKC_SUDO_BIN:-sudo}"
POWEROFF="${LPKLARKC_POWEROFF_TOOL:-/run/current-system/sw/bin/lpklarkc-poweroff}"
INTERVAL="${LPKLARKC_WATCHDOG_INTERVAL_SEC:-30}"
REQUIRED="${LPKLARKC_WATCHDOG_CONFIRMATIONS:-3}"
MAX_CYCLES="${LPKLARKC_WATCHDOG_MAX_CYCLES:-0}"
[[ "$INTERVAL" =~ ^[0-9]+$ && "$REQUIRED" =~ ^[1-9][0-9]*$ &&
   "$MAX_CYCLES" =~ ^[0-9]+$ ]] || exit 2
last=""
count=0
for ((i=1; ; i++)); do
  if status="$(timeout 15 "$IAP" instance-status 2>/dev/null)"; then
    case "$status" in
      SUSPENDED|TERMINATED)
        if [[ "$status" == "$last" ]]; then
          count=$((count+1))
        else
          last="$status"
          count=1
        fi
        if ((count >= REQUIRED)); then
          echo "Remote VM confirmed $status; powering off Dell (no hibernate)."
          exec "$SUDO" -n "$POWEROFF"
        fi
        ;;
      *) last=""; count=0 ;;
    esac
  else
    # Error, no network or missing Google auth is *not* a shutdown signal.
    last=""
    count=0
  fi
  if ((MAX_CYCLES>0 && i>=MAX_CYCLES)); then exit 0; fi
  sleep "$INTERVAL"
done
