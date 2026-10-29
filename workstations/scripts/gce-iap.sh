#!/usr/bin/env bash
# Google Cloud CLI credentials and IAP TCP forwarding for the Dell.
# The dedicated CLI config is restored from the trusted Ventoy USB.
# gcloud auth login, NOT application-default login, authenticates IAP.
set -euo pipefail
umask 077

PROJECT=argon-surf-472319-b0
ZONE=southamerica-east1-b
INSTANCE=wsklarkc
RDP_PORT=3389
LOCAL_PORT=13389
STATE="${LPKLARKC_STATE_TOOL:-/run/current-system/sw/bin/lpklarkc-state}"
GCLOUD="${LPKLARKC_GCLOUD_BIN:-gcloud}"
export CLOUDSDK_CONFIG="${LPKLARKC_GCLOUD_CONFIG:-/home/nixos/.config/lpklarkc-gcloud}"
export CLOUDSDK_CORE_DISABLE_USAGE_REPORTING=1

has_credentials() {
  [[ -s "$CLOUDSDK_CONFIG/credentials.db" &&
     -s "$CLOUDSDK_CONFIG/configurations/config_default" &&
     ! -L "$CLOUDSDK_CONFIG/credentials.db" &&
     ! -L "$CLOUDSDK_CONFIG/configurations/config_default" ]]
}

login() {
  if ! "$STATE" is-ready; then
    echo "Insert the trusted Ventoy USB before authorizing Google Cloud." >&2
    return 1
  fi
  mkdir -p "$CLOUDSDK_CONFIG/configurations"
  chmod 0700 "$CLOUDSDK_CONFIG" "$CLOUDSDK_CONFIG/configurations"

  echo "Google Cloud IAP pairing (first boot or reauthorization)."
  echo "Open the Google URL shown below on another device with a browser."
  echo "Copy its verification code back into this Dell terminal."
  echo "The CLI refresh credential will be saved on the UNENCRYPTED Ventoy USB."
  # Keep this interaction on the Dell's terminal, not a privileged process.
  # --no-launch-browser specifically supports using a second device.
  "$GCLOUD" auth login --no-launch-browser --project="$PROJECT"
  if ! has_credentials; then
    echo "Google login did not establish CLI credentials." >&2
    return 1
  fi
  sudo -n "$STATE" save
}

# Read-only; never starts, stops or changes the GCE instance.
instance_status() {
  export CLOUDSDK_CORE_DISABLE_PROMPTS=1
  if ! has_credentials; then
    echo "Google CLI credentials unavailable." >&2
    return 1
  fi
  "$GCLOUD" --quiet compute instances describe "$INSTANCE" \
    --project="$PROJECT" --zone="$ZONE" --format='value(status)'
}

check() {
  export CLOUDSDK_CORE_DISABLE_PROMPTS=1
  has_credentials || return 1
  # Only validate the refresh token when asked. Never print bearer tokens.
  "$GCLOUD" auth print-access-token >/dev/null 2>&1
}

# Resume-on-login: preserve the remote RAM/session; never auto-start TERMINATED.
# RUNNING alone does not prove XRDP ready, so the kiosk probes the RDP protocol.
ensure_running() {
  export CLOUDSDK_CORE_DISABLE_PROMPTS=1
  if ! has_credentials; then
    echo "No Google CLI credentials; authorize on trusted Ventoy USB." >&2
    return 1
  fi
  local interval="${LPKLARKC_GCE_POLL_SECONDS:-5}"
  local max_polls="${LPKLARKC_GCE_MAX_POLLS:-120}"
  if [[ ! "$interval" =~ ^[0-9]+$ || ! "$max_polls" =~ ^[1-9][0-9]*$ ]]; then
    echo "Invalid GCE polling interval/count." >&2
    return 2
  fi
  local status last="" resumed=false poll
  for ((poll=1; poll<=max_polls; poll++)); do
    if ! status="$(instance_status)"; then
      echo "Unable to query wsklarkc; check network/compute.instances.get." >&2
      return 1
    fi
    case "$status" in
      RUNNING)
        echo "Workstation running; checking XRDP next."
        return 0
        ;;
      SUSPENDED)
        if [[ "$resumed" == false ]]; then
          echo "Workstation suspended; resuming saved RAM/session..."
          if ! "$GCLOUD" --quiet compute instances resume "$INSTANCE" \
              --project="$PROJECT" --zone="$ZONE" --async >/dev/null; then
            echo "Resume failed; check compute.instances.resume, quota, capacity." >&2
            return 1
          fi
          resumed=true
        fi
        ;;
      TERMINATED|STOPPED)
        echo "Workstation is $status: session RAM unavailable. Refusing automatic start." >&2
        return 3
        ;;
      PROVISIONING|STAGING|PENDING|PENDING_STOP|STOPPING|SUSPENDING|REPAIRING)
        # Observe transitions without racing a controller or issuing start.
        ;;
      *)
        echo "Unexpected wsklarkc status: $status" >&2
        return 1
        ;;
    esac
    if [[ "$status" != "$last" ]]; then
      echo "Awaiting workstation: $status"
      last="$status"
    fi
    if ((poll < max_polls)); then sleep "$interval"; fi
  done
  echo "GCE did not become RUNNING; no stop/start fallback." >&2
  return 1
}

tunnel() {
  export CLOUDSDK_CORE_DISABLE_PROMPTS=1
  has_credentials || {
    echo "No Google CLI credentials. Run: lpklarkc-iap login" >&2
    return 1
  }
  # Listen exclusively on loopback. The destination VM requires no public IP.
  # No static IP, DDNS, WireGuard or Tailscale.
  exec "$GCLOUD" --quiet compute start-iap-tunnel "$INSTANCE" "$RDP_PORT" \
    --project="$PROJECT" --zone="$ZONE" \
    --local-host-port="127.0.0.1:$LOCAL_PORT"
}

case "${1:-}" in
  login) login ;;
  check) check ;;
  has-credentials) has_credentials ;;
  ensure-running) ensure_running ;;
  instance-status) instance_status ;;
  tunnel) tunnel ;;
  *)
    echo "Usage: lpklarkc-iap {login|check|has-credentials|ensure-running|instance-status|tunnel}" >&2
    exit 2
    ;;
esac
