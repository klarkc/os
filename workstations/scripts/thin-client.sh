#!/usr/bin/env bash
set -uo pipefail
echo "SOLO thin client - NixOS running from Ventoy"
echo "Only network recovery is local. Workstation login belongs to the server."

while ! nm-online -q -t 8; do
  echo "Wi-Fi unavailable; connect once using NetworkManager."
  nmtui || true
  sudo solo-client-state save || true
  sleep 2
done
sudo solo-client-state save || true

# tailscale status exit code is not sufficient to assert that an identity is
# authenticated. Require a usable IPv4 tailnet address.
while ! tailscale ip -4 2>/dev/null | grep -Eq '^100[.]'; do
  echo "Private network needs pairing. Follow the authentication URL below:"
  sudo tailscale up --accept-dns=true || true
  sudo solo-client-state save || true
  sleep 3
done
sudo solo-client-state save || true

while true; do
  host="$(sudo solo-client-state get-host 2>/dev/null || echo solo-workstation)"
  echo "Connecting to workstation: $host"
  echo "RDP will ask for your SERVER credentials, not a local login."
  xfreerdp /v:"$host" /f /dynamic-resolution /cert:tofu \
    /clipboard /network:auto /sec:tls || true
  echo "Disconnected. Retrying; Ctrl+C returns to client recovery."
  sleep 3
done
