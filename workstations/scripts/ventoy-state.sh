#!/usr/bin/env bash
# Persist Wi-Fi and the dedicated gcloud CLI identity on an EXISTING,
# trusted Ventoy USB. Never format or access the Dell's internal disk.
# The USB is intentionally NOT encrypted: possession exposes its secrets.
set -euo pipefail
umask 077

MOUNT=/run/solo-client/ventoy
DATA="$MOUNT/solo-client"
NM_DIR=/etc/NetworkManager/system-connections
GCLOUD_CONFIG=/home/nixos/.config/solo-gcloud
GCLOUD_STORE="$DATA/gcloud-cli"
GCLOUD_DB="$GCLOUD_CONFIG/credentials.db"
GCLOUD_DEFAULT="$GCLOUD_CONFIG/configurations/config_default"
FREERDP_DIR=/home/nixos/.config/freerdp
FREERDP_STORE="$DATA/freerdp"

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
    echo "Ventoy data partition not found. Refusing persistent Google login." >&2
    return 1
  fi

  device="$(readlink -f /dev/disk/by-label/Ventoy)"
  parent="$(lsblk -no PKNAME "$device" | head -n 1)"
  if [[ -z "$parent" ]]; then
    echo "Refusing Ventoy mount: parent disk not determined." >&2
    return 1
  fi
  transport="$(lsblk -dno TRAN "/dev/$parent" | head -n 1)"
  if [[ "$transport" != "usb" ]]; then
    echo "Refusing Ventoy mount: parent disk is not USB." >&2
    return 1
  fi

  fs="$(lsblk -no FSTYPE "$device" | head -n 1)"
  options="rw,nosuid,nodev,noexec"
  case "$fs" in
    exfat|vfat|ntfs|ntfs3) options="$options,uid=0,gid=0,umask=077" ;;
  esac
  if ! mount -o "$options" "$device" "$MOUNT"; then
    echo "Ventoy partition is not writable; nothing will be persisted." >&2
    return 1
  fi
  if ! (touch "$MOUNT/.solo-client-write-test" && rm "$MOUNT/.solo-client-write-test"); then
    echo "Ventoy data partition is not writable." >&2
    umount "$MOUNT" || true
    return 1
  fi
  mkdir -p "$DATA/wifi" "$GCLOUD_STORE"
  echo "Using trusted Ventoy USB for persistent Wi-Fi and gcloud CLI login."
}

restore_state() {
  prepare_usb || return 0
  mkdir -p "$NM_DIR"
  local profile
  for profile in "$DATA/wifi/"*.nmconnection; do
    [[ -f "$profile" && ! -L "$profile" ]] || continue
    install -m 0600 -- "$profile" "$NM_DIR/$(basename "$profile")"
  done

  # gcloud auth login stores CLI credentials in credentials.db, NOT in
  # application_default_credentials.json (ADC). Copy only the CLI database
  # and default account config; exclude access token caches and logs.
  if [[ -s "$GCLOUD_STORE/credentials.db" && -s "$GCLOUD_STORE/config_default" &&
        ! -L "$GCLOUD_STORE/credentials.db" && ! -L "$GCLOUD_STORE/config_default" ]]; then
    if [[ -L "$GCLOUD_CONFIG" || -L "$GCLOUD_CONFIG/configurations" ||
          -L "$GCLOUD_DB" || -L "$GCLOUD_DEFAULT" ]]; then
      echo "Refusing to restore Google credentials through symlinks." >&2
      return 1
    fi
    # The intermediate ~/.config directory must also be user-owned; otherwise
    # gcloud and sqlite cannot traverse it after a root boot-time restore.
    install -d -m 0700 -o nixos -g users /home/nixos/.config "$GCLOUD_CONFIG" "$GCLOUD_CONFIG/configurations"
    install -m 0600 -o nixos -g users -- "$GCLOUD_STORE/credentials.db" "$GCLOUD_DB"
    install -m 0600 -o nixos -g users -- "$GCLOUD_STORE/config_default" "$GCLOUD_DEFAULT"
  fi

  # FreeRDP 3 pins the server certificate under ~/.config/freerdp/server.
  # Reuse the pin after reboot; never weaken TLS to /cert:ignore.
  if [[ -d "$FREERDP_STORE/server" && ! -L "$FREERDP_STORE/server" ]]; then
    install -d -m 0700 -o nixos -g users /home/nixos/.config "$FREERDP_DIR" "$FREERDP_DIR/server"
    local cert
    for cert in "$FREERDP_STORE/server/"*.pem; do
      [[ -f "$cert" && ! -L "$cert" ]] || continue
      install -m 0600 -o nixos -g users -- "$cert" "$FREERDP_DIR/server/$(basename "$cert")"
    done
  fi
  if [[ -s "$FREERDP_STORE/known_hosts2" && ! -L "$FREERDP_STORE/known_hosts2" ]]; then
    install -d -m 0700 -o nixos -g users /home/nixos/.config "$FREERDP_DIR"
    install -m 0600 -o nixos -g users -- "$FREERDP_STORE/known_hosts2" "$FREERDP_DIR/known_hosts2"
  fi
}

save_state() {
  if ! is_ready; then
    echo "Ventoy persistence unavailable. Refusing to save secrets to any disk." >&2
    return 1
  fi
  mkdir -p "$DATA/wifi" "$GCLOUD_STORE"
  local profile temp
  for profile in "$NM_DIR/"*.nmconnection; do
    [[ -f "$profile" && ! -L "$profile" ]] || continue
    temp="$(mktemp "$DATA/wifi/.wifi.XXXXXXXX")"
    cp -- "$profile" "$temp"
    chmod 0600 "$temp"
    mv -f -- "$temp" "$DATA/wifi/$(basename "$profile")"
  done

  if [[ -s "$GCLOUD_DB" && -s "$GCLOUD_DEFAULT" &&
        ! -L "$GCLOUD_DB" && ! -L "$GCLOUD_DEFAULT" ]]; then
    # sqlite's online backup is consistent even while gcloud holds open
    # its source database. A plain cp during OAuth token refresh is not.
    temp="$(mktemp "$GCLOUD_STORE/.credentials.XXXXXXXX")"
    if ! sqlite3 "$GCLOUD_DB" ".backup '$temp'"; then
      rm -f -- "$temp"
      echo "Google credentials backup failed; previous USB copy retained." >&2
      return 1
    fi
    chmod 0600 "$temp"
    mv -f -- "$temp" "$GCLOUD_STORE/credentials.db"
    temp="$(mktemp "$GCLOUD_STORE/.config.XXXXXXXX")"
    cp -- "$GCLOUD_DEFAULT" "$temp"
    chmod 0600 "$temp"
    mv -f -- "$temp" "$GCLOUD_STORE/config_default"
  fi

  # Keep TOFU certificate pins across disposable live reboots.
  if [[ -d "$FREERDP_DIR/server" && ! -L "$FREERDP_DIR/server" ]]; then
    mkdir -p "$FREERDP_STORE/server"
    local cert
    for cert in "$FREERDP_DIR/server/"*.pem; do
      [[ -f "$cert" && ! -L "$cert" ]] || continue
      temp="$(mktemp "$FREERDP_STORE/server/.cert.XXXXXXXX")"
      cp -- "$cert" "$temp"
      chmod 0600 "$temp"
      mv -f -- "$temp" "$FREERDP_STORE/server/$(basename "$cert")"
    done
  fi
  if [[ -s "$FREERDP_DIR/known_hosts2" && ! -L "$FREERDP_DIR/known_hosts2" ]]; then
    mkdir -p "$FREERDP_STORE"
    temp="$(mktemp "$FREERDP_STORE/.known-hosts.XXXXXXXX")"
    cp -- "$FREERDP_DIR/known_hosts2" "$temp"
    chmod 0600 "$temp"
    mv -f -- "$temp" "$FREERDP_STORE/known_hosts2"
  fi

  sync -f "$MOUNT" || sync
  echo "State saved on Ventoy USB."
}

case "${1:-}" in
  restore) restore_state ;;
  save) save_state ;;
  is-ready) is_ready ;;
  *)
    echo "Usage: solo-client-state {restore|save|is-ready}" >&2
    exit 2
    ;;
esac
