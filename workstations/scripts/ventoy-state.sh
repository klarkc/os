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
  # A mountpoint alone does not prove the persistence destination is USB.
  # Never write credentials if a tmpfs, internal disk, ISO or VTOYEFI volume
  # has appeared at this path. Resolve device-mapper ancestry to raw USB data.
  local source fs raw resolved
  mountpoint -q "$MOUNT" || return 1
  source="$(findmnt -nro SOURCE --target "$MOUNT" 2>/dev/null | head -n1 || true)"
  fs="$(findmnt -nro FSTYPE --target "$MOUNT" 2>/dev/null | head -n1 || true)"
  [[ -b "$source" ]] || return 1
  case "$fs" in exfat|vfat|ntfs|ntfs3) ;; *) return 1 ;; esac
  usb_backing "$source" || return 1
  resolved="$(readlink -f "$source")"
  while IFS= read -r raw; do
    [[ "$resolved" == "$raw" ]] && return 0
    mapper_backs_raw "$source" "$raw" && return 0
  done < <(usb_raw_candidates)
  return 1
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

# Device-mapper aliases varied across Ventoy versions: /dev/mapper/sdX1
# (older), /dev/mapper/VentoyPart (1.1.18) or /dev/dm-N. Verify every
# backing device and only accept mappings of the USB data partition itself.
usb_raw_candidates() {
  local source resolved
  while IFS= read -r source; do
    [[ -b "$source" ]] || continue
    [[ "$(lsblk -no TYPE "$source" 2>/dev/null | head -n1)" == "part" ]] || continue
    usb_backing "$source" || continue
    resolved="$(readlink -f "$source")"
    [[ -b "$resolved" ]] || continue
    printf '%s\n' "$resolved"
  done < <(usb_candidates)
}

mapper_backs_raw() {
  local mapper="$1" raw="$2" actual directory slave
  [[ -b "$mapper" && -b "$raw" ]] || return 1
  mapper="$(readlink -f "$mapper")"
  raw="$(readlink -f "$raw")"
  [[ "$mapper" != "$raw" ]] || return 1
  directory="/sys/class/block/$(basename "$mapper")/slaves"
  [[ -d "$directory" ]] || return 1
  for slave in "$directory/"*; do
    [[ -e "$slave" ]] || continue
    actual="/dev/$(basename "$slave")"
    if [[ "$(readlink -f "$actual")" == "$raw" ]]; then
      return 0
    fi
    mapper_backs_raw "$actual" "$raw" && return 0
  done
  return 1
}

usb_mapper_candidates() {
  local raw mapped
  while IFS= read -r raw; do
    for mapped in /dev/mapper/* /dev/dm-*; do
      [[ -b "$mapped" ]] || continue
      mapper_backs_raw "$mapped" "$raw" || continue
      usb_backing "$mapped" || continue
      printf '%s\n' "$mapped"
    done
  done < <(usb_raw_candidates)
}

try_mount_usb() {
  local device="$1" fs options message
  [[ -b "$device" ]] && usb_backing "$device" || return 1
  fs="$(lsblk -no FSTYPE "$device" 2>/dev/null | head -n1 || true)"
  if [[ -z "$fs" ]]; then
    fs="$(blkid -p -o value -s TYPE "$device" 2>/dev/null || true)"
  fi
  options="rw,nosuid,nodev,noexec"
  case "$fs" in
    exfat|vfat|ntfs|ntfs3) options="$options,uid=0,gid=0,umask=077" ;;
    *) return 1 ;;
  esac

  if ! message="$(mount -o "$options" "$device" "$MOUNT" 2>&1)"; then
    printf 'USB mount unavailable: %s (%s): %s\n' "$device" "$fs" "$message" >&2
    return 1
  fi
  if ! (touch "$MOUNT/.solo-client-write-test" && rm "$MOUNT/.solo-client-write-test"); then
    echo "USB volume mounted but not writable: $device" >&2
    umount "$MOUNT" || true
    return 1
  fi
  mkdir -p "$DATA/wifi" "$GCLOUD_STORE"
  echo "Trusted Ventoy USB volume mounted: $device"
  return 0
}

create_usb_mapper() {
  local raw="$1" size name="solo-client-ventoy-data" mapped="/dev/mapper/solo-client-ventoy-data"
  [[ -b "$raw" ]] && usb_backing "$raw" || return 1
  [[ "$(lsblk -no TYPE "$raw" 2>/dev/null | head -n1)" == part ]] || return 1

  if [[ -e "$mapped" ]]; then
    # Never replace an unrelated mapping with the same name.
    mapper_backs_raw "$mapped" "$raw" && usb_backing "$mapped" || return 1
  else
    size="$(blockdev --getsz "$raw" 2>/dev/null || true)"
    [[ "$size" =~ ^[1-9][0-9]*$ ]] || return 1
    if ! dmsetup create "$name" --table "0 $size linear $raw 0" 2>/dev/null; then
      return 1
    fi
    udevadm settle --timeout=4 >/dev/null 2>&1 || true
  fi
  [[ -b "$mapped" ]] && mapper_backs_raw "$mapped" "$raw" && usb_backing "$mapped" || return 1
  printf '%s\n' "$mapped"
}

prepare_usb() {
  local device raw mapped attempt
  [[ "$(id -u)" -eq 0 ]] || { echo "USB recovery requires root." >&2; return 1; }
  mkdir -p "$MOUNT"
  if is_ready; then return 0; fi

  for attempt in 1 2 3; do
    udevadm settle --timeout=3 >/dev/null 2>&1 || true

    # Direct mounts first. They are normally available on recent Ventoy,
    # but may fail with EBUSY when the current ISO occupies this partition.
    while IFS= read -r device; do
      try_mount_usb "$device" && return 0
    done < <(usb_candidates)

    # Existing mapper aliases: 1.1.18 VentoyPart AND old /dev/mapper/sdX1.
    while IFS= read -r device; do
      try_mount_usb "$device" && return 0
    done < <(usb_mapper_candidates)

    # Official Ventoy recovery: create a DM-linear view of the verified
    # physical USB data partition when raw direct mounting stays busy.
    while IFS= read -r raw; do
      mapped="$(create_usb_mapper "$raw")" || continue
      try_mount_usb "$mapped" && return 0
    done < <(usb_raw_candidates)

    # Trigger udev before another attempt; do not format, repartition or
    # ever select an internal HDD.
    udevadm trigger --subsystem-match=block --action=change >/dev/null 2>&1 || true
    sleep 1
  done
  echo "Ventoy USB inaccessible: see 'solo-client-state diagnose' on Ctrl+Alt+F2." >&2
  return 1
}

diagnose_state() {
  echo "Solo Workstation - USB diagnostics (paths/labels only, no credentials)"
  lsblk -o NAME,PATH,TRAN,TYPE,FSTYPE,LABEL,SIZE,MOUNTPOINTS
  echo "Ventoy USB candidates:"
  usb_candidates || true
  echo "Mapped USB candidates:"
  usb_mapper_candidates || true
  echo "Current persistent mount:"
  findmnt -no SOURCE,FSTYPE,TARGET "$MOUNT" || true
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

ensure_state() {
  # On the Dell, the USB can become mountable only AFTER the original
  # boot-time restore has already exited. Mounting alone would lose Wi-Fi
  # settings and force Google login every boot. Restore the whitelist once.
  if is_ready; then return 0; fi
  restore_state || return 1
  is_ready || return 1
  if systemctl is-active --quiet NetworkManager.service; then
    nmcli connection reload || true
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
  ensure) ensure_state ;;
  diagnose) diagnose_state ;;
  *)
    echo "Usage: solo-client-state {restore|save|is-ready|ensure|diagnose}" >&2
    exit 2
    ;;
esac
