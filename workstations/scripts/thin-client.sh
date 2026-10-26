#!/usr/bin/env bash
# Autologin recovery console for the disposable Dell/Ventoy client.
# All Google credentials and the WireGuard private key are on the owner-
# trusted, unencrypted USB; never on the Dell's internal HDD.
set -uo pipefail

STATE="${SOLO_STATE_TOOL:-/run/current-system/sw/bin/solo-client-state}"
GCE="${SOLO_GCE_TOOL:-/run/current-system/sw/bin/solo-gce-endpoint}"
WIREGUARD="${SOLO_WG_TOOL:-/run/current-system/sw/bin/solo-client-wg}"
RDP_ADDRESS="10.77.0.1"

echo "SOLO thin client - NixOS running from Ventoy"
echo "Only network recovery is local. Your desktop and login are on the GCE server."

while ! nm-online -q -t 8; do
  echo "Network unavailable. Configure Wi-Fi with nmtui (only needed once)."
  nmtui || true
  sudo -n "$STATE" save || true
  sleep 2
done
sudo -n "$STATE" save || true

# Do not fall back to saving a key or OAuth grant on the internal HDD.
while ! sudo -n "$STATE" init-wg; do
  echo "Insert the trusted Ventoy USB. WireGuard cannot start without it."
  sleep 10
done

if ! "$GCE" has-credentials; then
  while ! "$GCE" login; do
    echo "Google read-only pairing incomplete. Retry from this console."
    sleep 10
  done
fi

echo "This client uses GCE instance discovery, not DuckDNS or a static IP."
echo "RDP target: $RDP_ADDRESS (WireGuard private tunnel, not public internet)."

while true; do
  record=""
  if ! record="$("$GCE" resolve)"; then
    echo "Workstation unavailable or WireGuard public metadata not provisioned."
    echo "Confirm GCE server is RUNNING and credentials have compute.instances.get."
    sleep 15
    continue
  fi

  IFS=$'\t' read -r endpoint server_public_key <<< "$record"
  if ! sudo -n "$WIREGUARD" connect "$endpoint" "$server_public_key"; then
    echo "WireGuard connection setup failed; check the USB identity and server."
    sleep 15
    continue
  fi

  echo "Connecting to workstation over encrypted WireGuard..."
  echo "RDP will request the SERVER password, never the Google API credential."
  xfreerdp /v:"$RDP_ADDRESS" /f /dynamic-resolution /cert:tofu \
    /clipboard /network:auto /sec:tls || true
  echo "Disconnected. Resolving GCE endpoint again (in case its public IP changed)."
  sleep 5
done
