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
export CLOUDSDK_CONFIG=/home/nixos/.config/lpklarkc-gcloud
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

check() {
  export CLOUDSDK_CORE_DISABLE_PROMPTS=1
  has_credentials || return 1
  # Only validate the refresh token when asked. Never print bearer tokens.
  "$GCLOUD" auth print-access-token >/dev/null 2>&1
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
  tunnel) tunnel ;;
  *)
    echo "Usage: lpklarkc-iap {login|check|has-credentials|tunnel}" >&2
    exit 2
    ;;
esac
