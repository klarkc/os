#!/usr/bin/env bash
# Persistent state on the *existing* Ventoy data partition.
# No format, partition, filesystem creation, or access to internal disks.
# USB is trusted by the owner. Contents are NOT encrypted.
set -euo pipefail

MOUNT=/run/solo-client/ventoy
DATA="$MOUNT/solo-client"
NM_DIR=/etc/NetworkManager/system-connections
TS_STATE=/var/lib/tailscale/tailscaled.state
ADC=/home/nixos/.config/gcloud/application_default_credentials.json
WG_DIR="$DATA/wireguard"
umask 077

is_ready() {
  mountpoint -q "$MOUNT"
}

prepare_usb() {
  local device parent transport fs options attempt
  mkdir -p "$MOUNT"
  if is_ready; then return 0; fi

  for attempt in $(seq 1 20); do
    if [[ -e /dev/disk/by-label/Ventoy ]]; then break; fi
    sleep 0.5
  done
  if [[ ! -e /dev/disk/by-label/Ventoy ]]; then
    echo "Ventoy data partition (label: Ventoy) not found: using volatile configuration." >&2
    return 1
  fi

  device="$(readlink -f /dev/disk/by-label/Ventoy)"
  parent="$(lsblk -no PKNAME "$device" | head -n 1)"
  if [[ -z "$parent" ]]; then
    echo "Refusing to mount Ventoy label: parent disk not determined." >&2
    return 1
  fi
  transport="$(lsblk -dno TRAN "/dev/$parent" | head -n 1)"
  if [[ "$transport" != "usb" ]]; then
    echo "Refusing to mount Ventoy label: parent transport is not USB." >&2
    return 1
  fi

  fs="$(lsblk -no FSTYPE "$device" | head -n 1)"
  options="rw,nosuid,nodev,noexec"
  case "$fs" in
    exfat|vfat|ntfs|ntfs3)
      options="$options,uid=0,gid=0,umask=077"
      ;;
  esac

  if ! mount -o "$options" "$device" "$MOUNT"; then
    echo "Cannot mount Ventoy data partition read/write; no state persisted." >&2
    return 1
  fi
  if ! (touch "$MOUNT/.solo-client-write-test" && rm "$MOUNT/.solo-client-write-test"); then
    echo "Ventoy data partition is not writable." >&2
    umount "$MOUNT" || true
    return 1
  fi
  mkdir -p "$DATA/wifi"
  echo "Using Ventoy USB for persistent Wi-Fi and Tailscale state."
}

restore_state() {
  prepare_usb || return 0
  mkdir -p "$NM_DIR" /var/lib/tailscale
  local profile
  for profile in "$DATA/wifi/"*.nmconnection; do
    [[ -f "$profile" && ! -L "$profile" ]] || continue
    cp -- "$profile" "$NM_DIR/$(basename "$profile")"
    chmod 0600 "$NM_DIR/$(basename "$profile")"
  done
  if [[ -s "$DATA/tailscaled.state" && ! -L "$DATA/tailscaled.state" ]]; then
    cp -- "$DATA/tailscaled.state" "$TS_STATE"
    chmod 0600 "$TS_STATE"
  fi
  # Only the restricted Compute Engine ADC credential is persisted. Never
  # copy the rest of ~/.config/gcloud, token caches or application logs.
  if [[ -s "$DATA/google-adc.json" && ! -L "$DATA/google-adc.json" ]]; then
    mkdir -p /home/nixos/.config/gcloud
    chown nixos:users /home/nixos/.config /home/nixos/.config/gcloud
    chmod 0700 /home/nixos/.config /home/nixos/.config/gcloud
    install -o nixos -g users -m 0600 -- "$DATA/google-adc.json" "$ADC"
  fi
}

save_state() {
  if ! is_ready; then
    echo "Ventoy persistence unavailable; skipping save." >&2
    return 1
  fi
  mkdir -p "$DATA/wifi"
  local profile temp
  for profile in "$NM_DIR/"*.nmconnection; do
    [[ -f "$profile" && ! -L "$profile" ]] || continue
    temp="$(mktemp "$DATA/wifi/.wifi.XXXXXXXX")"
    cp -- "$profile" "$temp"
    mv -f -- "$temp" "$DATA/wifi/$(basename "$profile")"
  done
  if [[ -s "$TS_STATE" ]]; then
    temp="$(mktemp "$DATA/.tailscale.XXXXXXXX")"
    cp -- "$TS_STATE" "$temp"
    mv -f -- "$temp" "$DATA/tailscaled.state"
  fi
  if [[ -s "$ADC" && ! -L "$ADC" ]]; then
    # The Ventoy mount is root-owned (umask=077). USB encryption is
    # intentionally NOT used; losing the drive exposes this OAuth grant.
    temp="$(mktemp "$DATA/.google-adc.XXXXXXXX")"
    cp -- "$ADC" "$temp"
    mv -f -- "$temp" "$DATA/google-adc.json"
  fi
  sync -f "$MOUNT" || sync
  echo "State saved on Ventoy USB."
}

init_wg() {
  prepare_usb || { echo "USB Ventoy is required for WireGuard keys." >&2; return 1; }
  mkdir -p "$WG_DIR"
  local temp
  if [[ ! -s "$WG_DIR/client.key" ]]; then
    temp="$(mktemp "$WG_DIR/.client-key.XXXXXXXX")"
    wg genkey > "$temp"
    # Do not overwrite a previously provisioned peer identity.
    if [[ ! -s "$WG_DIR/client.key" ]]; then
      mv -f -- "$temp" "$WG_DIR/client.key"
    else
      rm -f -- "$temp"
    fi
  fi
  temp="$(mktemp "$WG_DIR/.client-pub.XXXXXXXX")"
  wg pubkey < "$WG_DIR/client.key" > "$temp"
  mv -f -- "$temp" "$WG_DIR/client.pub"
  sync -f "$WG_DIR/client.key"
}

set_host() {
  local hostname="${1:-}"
  if [[ ! "$hostname" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "Invalid Tailscale hostname or IP." >&2
    exit 2
  fi
  is_ready || { echo "Ventoy is not mounted." >&2; exit 1; }
  printf '%s\n' "$hostname" > "$DATA/rdp-host"
  sync -f "$DATA/rdp-host"
}

get_host() {
  if is_ready && [[ -s "$DATA/rdp-host" ]]; then
    head -n 1 "$DATA/rdp-host"
  else
    printf 'solo-workstation\n'
  fi
}

case "${1:-}" in
  restore) restore_state ;;
  save) save_state ;;
  is-ready) is_ready ;;
  init-wg) init_wg ;;
  wg-public)
    init_wg
    cat "$WG_DIR/client.pub"
    ;;
  set-host) set_host "${2:-}" ;;
  get-host) get_host ;;
  *) echo "Usage: solo-client-state {restore|save|is-ready|init-wg|wg-public|get-host|set-host HOST}" >&2; exit 2 ;;
esac
