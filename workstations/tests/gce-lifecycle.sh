#!/usr/bin/env bash
# Cloud-free tests for SUSPENDED→resume, RUNNING, TERMINATED and errors.
set -euo pipefail
script="${1:?Usage: gce-lifecycle.sh path/to/gce-iap.sh}"
[[ -f "$script" ]] || exit 2
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/config/configurations" "$tmp/bin"
printf 'synthetic-ci-creds\n' > "$tmp/config/credentials.db"
printf '[core]\naccount = ci@example.invalid\n' > "$tmp/config/configurations/config_default"
cat > "$tmp/bin/gcloud" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$LPKLARKC_TEST_CALLS"
case " $* " in
  *" compute instances describe wsklarkc "*)
    [[ "$*" == *"--project=argon-surf-472319-b0"* &&
       "$*" == *"--zone=southamerica-east1-b"* &&
       "$*" == *"--format=value(status)"* ]] || exit 97
    [[ "${LPKLARKC_TEST_DENY_GET:-0}" != 1 ]] || exit 41
    n="$(cat "$LPKLARKC_TEST_COUNTER")"
    n=$((n+1))
    printf '%s\n' "$n" > "$LPKLARKC_TEST_COUNTER"
    line="$(sed -n "${n}p" "$LPKLARKC_TEST_SEQUENCE")"
    [[ -n "$line" ]] || line="$(tail -n 1 "$LPKLARKC_TEST_SEQUENCE")"
    printf '%s\n' "$line"
    ;;
  *" compute instances resume wsklarkc "*)
    [[ "$*" == *"--project=argon-surf-472319-b0"* &&
       "$*" == *"--zone=southamerica-east1-b"* &&
       "$*" == *"--async"* ]] || exit 96
    [[ "${LPKLARKC_TEST_DENY_RESUME:-0}" != 1 ]] || exit 43
    ;;
  *) printf 'Forbidden/unexpected gcloud call: %s\n' "$*" >&2; exit 99 ;;
esac
MOCK
chmod 700 "$tmp/bin/gcloud"
export LPKLARKC_GCLOUD_BIN="$tmp/bin/gcloud"
export LPKLARKC_GCLOUD_CONFIG="$tmp/config"
export LPKLARKC_TEST_CALLS="$tmp/calls"
export LPKLARKC_TEST_COUNTER="$tmp/counter"
export LPKLARKC_TEST_SEQUENCE="$tmp/sequence"
export LPKLARKC_GCE_POLL_SECONDS=0 LPKLARKC_GCE_MAX_POLLS=6
reset() {
  : > "$LPKLARKC_TEST_CALLS"
  printf '0\n' > "$LPKLARKC_TEST_COUNTER"
  printf '%s\n' "$@" > "$LPKLARKC_TEST_SEQUENCE"
}
run_ok() {
  local expected="$1" got
  shift
  reset "$@"
  bash "$script" ensure-running >/dev/null
  got="$(grep -c 'compute instances resume wsklarkc' "$LPKLARKC_TEST_CALLS" || true)"
  [[ "$got" == "$expected" ]] || { echo "expected $expected resumes, got $got" >&2; exit 1; }
}
run_fail() {
  local expected="$1" got
  shift
  reset "$@"
  if bash "$script" ensure-running >/dev/null 2>&1; then
    echo "FAIL: invalid state unexpectedly allowed" >&2
    exit 1
  fi
  got="$(grep -c 'compute instances resume wsklarkc' "$LPKLARKC_TEST_CALLS" || true)"
  [[ "$got" == "$expected" ]] || { echo "expected $expected resume attempts, got $got" >&2; exit 1; }
}
run_ok 0 RUNNING
run_ok 1 SUSPENDED PROVISIONING STAGING RUNNING
run_ok 1 SUSPENDING SUSPENDED PROVISIONING RUNNING
run_ok 0 PROVISIONING STAGING RUNNING
run_fail 0 TERMINATED
run_fail 0 STOPPED
run_fail 0 STOPPING TERMINATED
run_fail 0 UNKNOWN
run_fail 1 SUSPENDED SUSPENDED SUSPENDED SUSPENDED SUSPENDED SUSPENDED
export LPKLARKC_TEST_DENY_GET=1
run_fail 0 RUNNING
unset LPKLARKC_TEST_DENY_GET
export LPKLARKC_TEST_DENY_RESUME=1
run_fail 1 SUSPENDED
unset LPKLARKC_TEST_DENY_RESUME
mv "$tmp/config/credentials.db" "$tmp/config/credentials.db.hidden"
run_fail 0 SUSPENDED
mv "$tmp/config/credentials.db.hidden" "$tmp/config/credentials.db"
export LPKLARKC_GCE_MAX_POLLS=bad
run_fail 0 SUSPENDED
echo "PASS: GCE lifecycle refuses start/stop and only resumes SUSPENDED"
