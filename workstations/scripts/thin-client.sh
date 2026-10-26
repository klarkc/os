#!/usr/bin/env bash
# Boot console: Wi-Fi -> trusted Ventoy state -> Google IAP -> FreeRDP.
# Only Wi-Fi recovery and Google authorization require local interaction.
set -uo pipefail

STATE="${SOLO_STATE_TOOL:-/run/current-system/sw/bin/solo-client-state}"
IAP="${SOLO_IAP_TOOL:-/run/current-system/sw/bin/solo-gce-iap}"
RDP_ADDRESS="127.0.0.1:13389"
TUNNEL_PID=""
TUNNEL_LOG=""

cleanup() {
  if [[ -n "$TUNNEL_PID" ]]; then
    kill "$TUNNEL_PID" 2>/dev/null || true
    wait "$TUNNEL_PID" 2>/dev/null || true
  fi
  [[ -z "$TUNNEL_LOG" ]] || rm -f -- "$TUNNEL_LOG"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "Solo thin client - NixOS Live from Ventoy"
echo "Google Cloud IAP provides the private connection to your workstation."

while true; do
  while ! nm-online -q -t 8; do
    echo "Wi-Fi not connected. Configure with nmtui."
    nmtui || true
    sudo -n "$STATE" save || true
    sleep 2
  done

  while ! "$STATE" is-ready; do
    echo "Ventoy USB missing. Authentication will not run without it."
    sleep 10
  done
  sudo -n "$STATE" save || true

  if ! "$IAP" has-credentials; then
    until "$IAP" login; do
      echo "Google authorization incomplete. Retry after checking Wi-Fi."
      sleep 10
    done
  fi

  echo "Opening IAP tunnel to solo-workstation:3389..."
  TUNNEL_LOG="$(mktemp)"
  "$IAP" tunnel >"$TUNNEL_LOG" 2>&1 &
  TUNNEL_PID=$!

  # The gcloud process must remain alive and confirm its own listener.
  # Merely connecting to an arbitrary local port is not sufficient proof.
  ready=false
  for ((attempt = 0; attempt < 65; attempt++)); do
    if ! kill -0 "$TUNNEL_PID" 2>/dev/null; then break; fi
    if grep -qF 'Listening on port [13389]' "$TUNNEL_LOG" &&
       nc -z -w 1 127.0.0.1 13389 2>/dev/null; then
      ready=true
      break
    fi
    sleep 1
  done

  if [[ "$ready" == true ]]; then
    echo "IAP connected locally. Opening fullscreen RDP."
    echo "The XRDP login is the SERVER account, not your Google password."
    xfreerdp /v:"$RDP_ADDRESS" /f /dynamic-resolution \
      /cert:tofu /clipboard /network:auto /sec:tls || true
    echo "RDP disconnected. Reconnecting via IAP..."
  else
    echo "Unable to establish IAP tunnel. Check that the GCE VM is running,"
    echo "IAM permits IAP TCP port 3389, and server firewall allows IAP."
    # Reauthorization after an expired/revoked login. Internet disruption
    # is not automatically interpreted as revoked credentials.
    if nm-online -q -t 3 && ! "$IAP" check; then
      echo "Google login could not be refreshed; reauthorization required."
      "$IAP" login || true
    fi
  fi

  cleanup
  TUNNEL_PID=""
  TUNNEL_LOG=""
  sleep 5
done
