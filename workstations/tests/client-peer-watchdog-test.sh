#!/usr/bin/env bash
# Cloud-free regression: only persistent confirmed SUSPENDED/TERMINATED
# states can shut down Dell; network errors and transient states cannot.
set -euo pipefail
script="${1:?Usage: client-peer-watchdog-test.sh path/to/watchdog.sh path/to/thin-client.sh}"
kiosk="${2:?Usage: client-peer-watchdog-test.sh path/to/watchdog.sh path/to/thin-client.sh}"
[[ -f "$script" && -f "$kiosk" ]] || exit 2
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
cat > "$tmp/iap" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == instance-status ]] || exit 90
n="$(cat "$LPKLARKC_TEST_COUNTER")"
n=$((n+1))
printf '%s\n' "$n" > "$LPKLARKC_TEST_COUNTER"
status="$(sed -n "${n}p" "$LPKLARKC_TEST_SEQUENCE")"
[[ -n "$status" ]] || status=RUNNING
[[ "$status" != ERROR ]] || exit 23
printf '%s\n' "$status"
MOCK
cat > "$tmp/sudo" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == -n && "$2" == "$LPKLARKC_POWEROFF_TOOL" ]] || exit 99
printf 'poweroff\n' >> "$LPKLARKC_TEST_POWER_OFF"
MOCK
chmod 700 "$tmp/iap" "$tmp/sudo"
export LPKLARKC_IAP_TOOL="$tmp/iap"
export LPKLARKC_SUDO_BIN="$tmp/sudo"
export LPKLARKC_POWEROFF_TOOL="$tmp/fake-poweroff"
export LPKLARKC_TEST_POWER_OFF="$tmp/poweroff"
export LPKLARKC_TEST_COUNTER="$tmp/counter"
export LPKLARKC_TEST_SEQUENCE="$tmp/sequence"
export LPKLARKC_WATCHDOG_INTERVAL_SEC=0
export LPKLARKC_WATCHDOG_CONFIRMATIONS=3
export LPKLARKC_WATCHDOG_MAX_CYCLES=8
run_case() {
  local expected="$1" count
  shift
  printf '0\n' > "$LPKLARKC_TEST_COUNTER"
  : > "$LPKLARKC_TEST_POWER_OFF"
  printf '%s\n' "$@" > "$LPKLARKC_TEST_SEQUENCE"
  bash "$script" >/dev/null
  count="$(wc -l < "$LPKLARKC_TEST_POWER_OFF" | tr -d '[:space:]')"
  [[ "$count" == "$expected" ]] || { echo "wanted $expected poweroffs; got $count" >&2; exit 1; }
}
run_case 0 RUNNING SUSPENDED RUNNING SUSPENDED ERROR SUSPENDED RUNNING RUNNING
run_case 0 SUSPENDED SUSPENDED ERROR SUSPENDED SUSPENDED RUNNING RUNNING RUNNING
run_case 1 RUNNING SUSPENDED SUSPENDED SUSPENDED
run_case 1 TERMINATED TERMINATED TERMINATED
run_case 0 STOPPING STOPPING SUSPENDING SUSPENDING PROVISIONING RUNNING RUNNING RUNNING
# Regression for the KIOSK'S INDEPENDENT two-read state confirmation:
# a transient, contradictory or unavailable GCE response must not shut
# down Dell. The read-only --check-peer-stopped entrypoint uses the SAME
# injected mock instance-status implementation; no gcloud/network/sudo.
run_kiosk_case() {
  local expected="$1" result count
  shift
  printf '0\n' > "$LPKLARKC_TEST_COUNTER"
  : > "$LPKLARKC_TEST_POWER_OFF"
  printf '%s\n' "$@" > "$LPKLARKC_TEST_SEQUENCE"
  if bash "$kiosk" --check-peer-stopped >"$tmp/kiosk.log" 2>&1; then
    result=0
  else
    result=$?
  fi
  if [[ "$expected" == pass && "$result" -ne 0 ]] ||
     [[ "$expected" == fail && "$result" -eq 0 ]]; then
    printf 'kiosk expected %s for statuses %s, got exit %s\n' "$expected" "$*" "$result" >&2
    cat "$tmp/kiosk.log" >&2
    exit 1
  fi
  count="$(wc -l < "$LPKLARKC_TEST_POWER_OFF" | tr -d '[:space:]')"
  [[ "$count" == 0 ]] || { echo "read-only kiosk precheck called poweroff" >&2; exit 1; }
}
run_kiosk_case fail ERROR ERROR
run_kiosk_case fail RUNNING RUNNING
run_kiosk_case fail SUSPENDING SUSPENDED
run_kiosk_case fail SUSPENDED ERROR
run_kiosk_case fail SUSPENDED TERMINATED
run_kiosk_case fail TERMINATED SUSPENDED
run_kiosk_case pass SUSPENDED SUSPENDED
run_kiosk_case pass TERMINATED TERMINATED
echo "PASS: watchdog and kiosk require confirmed final GCE state; network failures deny"
