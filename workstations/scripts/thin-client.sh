#!/usr/bin/env bash
set -uo pipefail

echo "SOLO Thin Client (session only; no local disk installation)"
echo "Network status: "
nmcli -t -f STATE general status || true
while ! nm-online -q -t 8; do
  echo "Configure Wi-Fi in NetworkManager (this stays in volatile RAM)."
  nmtui || true
  sleep 1
done
echo "Network connected. Authenticating private tailnet..."
while ! tailscale status >/dev/null 2>&1; do
  echo "Use the sign-in URL shown below on your phone; no secret is preinstalled."
  sudo tailscale up --accept-dns=false || true
  tailscale status || true
  sleep 5
done
while true; do
  echo
  echo "Enter the Tailscale hostname/IP of your WORKSTATION (not its public IP)."
  read -rp "Workstation [solo-workstation]: " host
  host="${host:-solo-workstation}"
  if [[ ! "$host" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "Invalid destination"
    continue
  fi
  # Request the server's login at the RDP endpoint. No password in process
  # arguments, public Git, Nix store, or the client startup script.
  echo "Connecting to $host. Log in using the SERVER's XRDP screen."
  xfreerdp /v:"$host" /f /dynamic-resolution /cert:tofu /network:auto /sec:tls \
    /clipboard /audio-mode:0 || true
  echo "Remote session disconnected. Press Ctrl+C here to configure again."
  sleep 3
done
