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

# Walk the kernel's real block-device ancestry, including device-mapper.
# Never accept the internal disk merely because it has a Ventoy-like label.
usb_backing() {
  local node="$1" name sys slave parent count=0
  [[ -b "$node" ]] || return 1
  name="$(basename "$(readlink -f -- "$node")")"
  sys="/sys/class/block/$name"
  [[ -d "$sys" ]] || return 1

  # Ventoy 1.1.18 exposes the remountable partition via a DM-linear mapping
  # at /dev/mapper/VentoyPart. Verify EVERY underlying device is on USB.
  for slave in "$sys/slaves/"*; do
    [[ -e "$slave" ]] || continue
    count=$((count + 1))
    usb_backing "/dev/$(basename "$slave")" || return 1
  done
  if (( count > 0 )); then return 0; fi

  if [[ "$(lsblk -dno TRAN "$node" 2>/dev/null | head -n1)" == "usb" ]]; then
    return 0
  fi
  parent="$(lsblk -no PKNAME "$node" 2>/dev/null | head -n1 || true)"
  [[ -n "$parent" && "$parent" != "$name" ]] || return 1
  usb_backing "/dev/$parent"
}

usb_candidates() {
  # Prefer original labelled partition; when Ventoy uses its DM remount
  # path, follow it, but ONLY if its backing device is physical USB.
  local source efi disk part fs count=0
  source="/dev/disk/by-label/Ventoy"
  if [[ -e "$source" ]] && usb_backing "$source"; then
    printf '%s\n' "$source"
  fi
  source="/dev/mapper/VentoyPart"
  if [[ -b "$source" ]] && usb_backing "$source"; then
    printf '%s\n' "$source"
  fi

  # Ventoy allows relabelling partition 1 (-L option). Find it using the
  # 32 MB VTOYEFI partition, then require exactly ONE same-disk data partition.
  efi="/dev/disk/by-label/VTOYEFI"
  [[ -e "$efi" ]] && usb_backing "$efi" || return 0
  disk="$(lsblk -no PKNAME "$efi" | head -n1)"
  [[ -n "$disk" ]] || return 0
  local chosen=""
  while read -r part fs; do
    [[ -b "$part" ]] || continue
    [[ "$(readlink -f "$part")" != "$(readlink -f "$efi")" ]] || continue
    [[ "$(lsblk -no TYPE "$part" | head -n1)" == "part" ]] || continue
    case "$fs" in exfat|vfat|ntfs|ntfs3) ;; *) continue ;; esac
    usb_backing "$part" || continue
    count=$((count + 1))
    chosen="$part"
  done < <(lsblk -rno PATH,FSTYPE "/dev/$disk")
  if (( count == 1 )); then printf '%s\n' "$chosen"; fi
}

prepare_usb() {
  local device fs options attempt
  [[ "$(id -u)" == 0 ]] || { echo "USB recovery requires root." >&2; return 1; }
  mkdir -p "$MOUNT"
  if is_ready; then return 0; fi

  # A failed boot-time USB discovery is NOT permanent. Poll again after
  # Wi-Fi pairing and on every recovery attempt.
  for attempt in 1 2 3; do
    udevadm settle --timeout=3 >/dev/null 2>&1 || true
    while IFS= read -r device; do
      [[ -b "$device" ]] || continue
      usb_backing "$device" || continue
      fs="$(lsblk -no FSTYPE "$device" 2>/dev/null | head -n1)"
      if [[ -z "$fs" ]]; then
        fs="$(blkid -o value -s TYPE "$device" 2>/dev/null || true)"
      fi
      options="rw,nosuid,nodev,noexec"
      case "$fs" in
        exfat|vfat|ntfs|ntfs3)
          options="$options,uid=0,gid=0,umask=077"
          ;;
        *) continue ;;
      esac

      if ! mount -o "$options" "$device" "$MOUNT" 2>/dev/null; then
        continue
      fi
      if ! (touch "$MOUNT/.solo-client-write-test" && rm "$MOUNT/.solo-client-write-test"); then
        umount "$MOUNT" || true
        continue
      fi
      mkdir -p "$DATA/wifi" "$GCLOUD_STORE"
      echo "Trusted USB persistence mounted from $device."
      return 0
    done < <(usb_candidates)
    sleep 1
  done
  echo "Ventoy data volume still unavailable (label, device-mapper, or VTOYEFI)." >&2
  return 1
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
  ensure) prepare_usb ;;
  *)
    echo "Usage: solo-client-state {restore|save|is-ready|ensure}" >&2
    exit 2
    ;;
esac
