#!/usr/bin/env bash
# Production IAP -> localhost:13389 -> FreeRDP 3 -> XRDP login -> XMonad.
# CI service account is allowed OS Admin Login + IAP ports 22/3389
# ONLY for wsklarkc. Not the same identity/credentials as the Dell user.
# Disposable password is generated in RAM, sent via SSH stdin and FreeRDP
# stdin; NEVER argv, metadata, Git, Nix store or CI logs/artifacts.
set -euo pipefail
umask 077
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
export CLOUDSDK_CORE_DISABLE_USAGE_REPORTING=1

mode="${1:-}"
[[ "$mode" == initial || "$mode" == reconnect || "$mode" == cleanup ]] || {
  echo "Usage: $0 {initial|reconnect|cleanup}" >&2
  exit 2
}
project=argon-surf-472319-b0
zone=southamerica-east1-b
vm=wsklarkc
user=wsklarkcci
port=13389
guest_path="/tmp/wsklarkc-e2e-guest-${GITHUB_RUN_ID:-manual}.sh"

for cmd in gcloud openssl timeout bash; do
  command -v "$cmd" >/dev/null || { echo "FAIL: missing $cmd" >&2; exit 2; }
done
[[ "${GITHUB_REPOSITORY:-}" == klarkc/os &&
   "${GITHUB_REF:-}" == refs/heads/feat/wsklarkc-gce ]] || {
  echo "FAIL: E2E must execute on the trusted BuildGCE branch" >&2
  exit 2
}
tmp="$(mktemp -d)"
rdp_pid=""
tunnel_pid=""
password=""
cleanup_local() {
  if [[ -n "$rdp_pid" ]]; then
    kill "$rdp_pid" >/dev/null 2>&1 || true
    wait "$rdp_pid" 2>/dev/null || true
  fi
  if [[ -n "$tunnel_pid" ]]; then
    kill "$tunnel_pid" >/dev/null 2>&1 || true
    wait "$tunnel_pid" 2>/dev/null || true
  fi
  unset password
  rm -rf -- "$tmp"
}
trap cleanup_local EXIT

ssh_guest() {
  local command="$1"
  gcloud compute ssh "$vm" --project="$project" --zone="$zone" \
    --tunnel-through-iap --quiet --command="sudo -n bash $guest_path $command"
}
# No credential data is copied; the guest script contains only code.
gcloud compute scp workstations/scripts/gce-rdp-guest-e2e.sh \
  "$vm:$guest_path" --project="$project" --zone="$zone" \
  --tunnel-through-iap --quiet >/dev/null

if [[ "$mode" == cleanup ]]; then
  ssh_guest cleanup
  gcloud compute ssh "$vm" --project="$project" --zone="$zone" \
    --tunnel-through-iap --quiet --command="rm -f $guest_path" >/dev/null || true
  echo "PASS: temporary guest account cleaned without touching klarkc"
  exit 0
fi

# Stop/start must not erase the temporary account's HOME marker.
if [[ "$mode" == reconnect ]]; then
  ssh_guest marker
fi

password="$(openssl rand -hex 24)"
printf '%s\n' "$password" | ssh_guest setup >/dev/null
echo "PASS: disposable password securely set over IAP+SSH"

# This copies the Dell's canonical tunnel destination and loopback binding.
gcloud --quiet compute start-iap-tunnel "$vm" 3389 \
  --project="$project" --zone="$zone" \
  --local-host-port="127.0.0.1:$port" \
  >"$tmp/iap-stdout" 2>"$tmp/iap-stderr" &
tunnel_pid=$!

ready=0
for attempt in $(seq 1 60); do
  if ! kill -0 "$tunnel_pid" 2>/dev/null; then break; fi
  if timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
if [[ "$ready" != 1 ]]; then
  echo "FAIL: authorized IAP tunnel did not reach TCP 3389" >&2
  exit 1
fi
echo "PASS: Google IAP tunnel opened to remote 3389 on localhost:$port"
echo "NOTE: TCP success is not sufficient; full XRDP login checked below"

freerdp=""
if command -v xfreerdp3 >/dev/null 2>&1; then
  freerdp=xfreerdp3
elif command -v xfreerdp >/dev/null 2>&1; then
  freerdp=xfreerdp
else
  echo "FAIL: FreeRDP X11 client unavailable" >&2
  exit 2
fi
command -v xvfb-run >/dev/null || { echo "FAIL: no virtual X11 display" >&2; exit 2; }

# The fake X11 server exists only inside the GitHub runner. FreeRDP uses
# TLS TOFU (not /cert:ignore) and consumes password from stdin. No argv
# secrets and no remote xrdp configuration changes.
printf '%s\n' "$password" | xvfb-run --auto-servernum \
  --server-args="-screen 0 1280x720x24" \
  "$freerdp" "/u:$user" "/v:127.0.0.1:$port" \
  /sec:tls /cert:tofu /from-stdin:force /size:1280x720 \
  /dynamic-resolution /log-level:ERROR \
  >"$tmp/freerdp.log" 2>&1 &
rdp_pid=$!
unset password

# Fail if FreeRDP exits before an actual user XMonad process appears.
authenticated=0
for attempt in $(seq 1 35); do
  if ! kill -0 "$rdp_pid" 2>/dev/null; then
    echo "FAIL: FreeRDP exited before authenticated graphical session" >&2
    exit 1
  fi
  if ssh_guest verify >"$tmp/remote-status" 2>/dev/null; then
    authenticated=1
    break
  fi
  sleep 2
done
if [[ "$authenticated" != 1 ]]; then
  echo "FAIL: no server-side authenticated XRDP/XMonad session" >&2
  exit 1
fi
[[ -n "$rdp_pid" ]] && kill -0 "$rdp_pid" 2>/dev/null || {
  echo "FAIL: FreeRDP connection ended immediately after authentication" >&2
  exit 1
}
echo "PASS: FreeRDP authenticated via TLS+IAP and spawned user-owned XMonad"
echo "PASS: true RDP graphical session established, not only TCP handshake"
if [[ "$mode" == reconnect ]]; then
  echo "PASS: reconnect after GCE stop/start with the same persistent HOME"
fi
