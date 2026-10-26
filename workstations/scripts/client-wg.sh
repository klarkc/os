#!/usr/bin/env bash
# Privileged, deliberately narrow WireGuard setup for the USB thin client.
# Never uses an internal disk; never installs a default route or forwards RDP
# outside the private 10.77.0.1/32 peer endpoint.
set -euo pipefail

IFACE="solo-wg"
PRIVATE_KEY="/run/solo-client/ventoy/solo-client/wireguard/client.key"
SERVER_IP="10.77.0.1"
CLIENT_IP="10.77.0.2"
PORT="51820"

validate_ipv4() {
  local ip="$1" octet
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local -a octets
  IFS=. read -r -a octets <<< "$ip"
  [[ "${#octets[@]}" == 4 ]] || return 1
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^(0|[1-9][0-9]{0,2})$ ]] || return 1
    (( 10#$octet <= 255 )) || return 1
  done
}

validate_peer() {
  [[ "$1" =~ ^[a-zA-Z0-9+/]{43}=$ ]] || return 1
  [[ "$(printf '%s' "$1" | base64 --decode | wc -c)" -eq 32 ]] || return 1
}

connect() {
  local endpoint="${1:-}" peer="${2:-}" previous
  [[ "$(id -u)" -eq 0 ]] || { echo "Root privileges required." >&2; return 1; }
  validate_ipv4 "$endpoint" || { echo "Invalid GCE IPv4 address." >&2; return 2; }
  validate_peer "$peer" || { echo "Invalid WireGuard server public key." >&2; return 2; }
  mountpoint -q /run/solo-client/ventoy || { echo "Missing trusted Ventoy USB." >&2; return 1; }
  [[ -s "$PRIVATE_KEY" && ! -L "$PRIVATE_KEY" ]] || { echo "Missing USB WireGuard identity." >&2; return 1; }

  modprobe wireguard 2>/dev/null || true
  if ! ip link show dev "$IFACE" >/dev/null 2>&1; then
    ip link add dev "$IFACE" type wireguard
  fi
  # Old peers must not remain accepted if server identity is rotated.
  for previous in $(wg show "$IFACE" peers); do
    if [[ "$previous" != "$peer" ]]; then
      wg set "$IFACE" peer "$previous" remove
    fi
  done
  wg set "$IFACE" private-key "$PRIVATE_KEY" \
    peer "$peer" allowed-ips "$SERVER_IP/32" \
    endpoint "$endpoint:$PORT" persistent-keepalive 25
  ip -4 address replace "$CLIENT_IP/32" dev "$IFACE"
  ip link set "$IFACE" up
  ip -4 route replace "$SERVER_IP/32" dev "$IFACE" scope link
  echo "Private route to $SERVER_IP configured (GCE endpoint $endpoint:$PORT)."
}

case "${1:-}" in
  connect) connect "${2:-}" "${3:-}" ;;
  *)
    echo "Usage: solo-client-wg connect GCE_PUBLIC_IPV4 SERVER_WG_PUBLIC_KEY" >&2
    exit 2
    ;;
esac
