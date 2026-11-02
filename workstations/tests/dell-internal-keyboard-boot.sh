#!/usr/bin/env bash
# RED-before-GREEN Dell regression: generic live boot must preserve keyboards;
# optional Dell boot must supply i8042.nokbd without disabling USB HID/xHCI.
# --iso validates the actual BIOS and EFI bootloader kernel command lines.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { printf 'FAIL: Dell keyboard boot regression: %s\n' "$*" >&2; exit 1; }
mode="--eval"
if (( $# > 0 )); then mode="$1"; fi
[[ "$mode" == "--eval" || "$mode" == "--iso" ]] || fail "usage: $0 [--eval | --iso path/to.iso]"
[[ "$mode" != "--iso" || $# -eq 2 ]] || fail "--iso requires exactly one ISO file"
cfg=".#nixosConfigurations.lpklarkc.config"

default_params="$(nix eval --json "$cfg.boot.kernelParams")"
printf '%s\n' "$default_params" | jq -e 'index("i8042.nokbd") == null' >/dev/null ||
  fail "generic DEFAULT would disable internal keyboards on unrelated laptops"

usb_modules="$(nix eval --json "$cfg.boot.initrd.availableKernelModules")"
printf '%s\n' "$usb_modules" |
  jq -e 'index("xhci_pci") != null and index("usb_storage") != null and index("uas") != null' >/dev/null ||
  fail "USB/xHCI controller modules disappeared from the live image"
for attr in isoImage.makeBiosBootable isoImage.makeEfiBootable isoImage.makeUsbBootable isoImage.showConfiguration; do
  [[ "$(nix eval --json "$cfg.$attr")" == true ]] ||
    fail "$attr must remain true for selectable BIOS/EFI live-boot entries"
done

# EXPECTED BASELINE RED: no Dell specialisation exists yet. Never accept
# a commented kernel option or one in an unevaluated Nix expression.
if ! dell_params="$(nix eval --json "$cfg.specialisation.dell-internal-keyboard-off.configuration.boot.kernelParams" 2>/dev/null)"; then
  fail "missing selectable Dell boot configuration with i8042.nokbd (EXPECTED RED on baseline)"
fi
printf '%s\n' "$dell_params" |
  jq -e '[.[] | select(. == "i8042.nokbd")] | length == 1' >/dev/null ||
  fail "Dell-specific evaluated kernel parameters must contain exactly one i8042.nokbd"

if [[ "$mode" == "--iso" ]]; then
  iso="$2"
  [[ -s "$iso" ]] || fail "built ISO not found: $iso"
  command -v xorriso >/dev/null 2>&1 || fail "xorriso is required to inspect the built ISO"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  xorriso -osirrox on -indev "$iso" -extract /isolinux/isolinux.cfg "$tmp/bios.cfg" >/dev/null 2>&1 ||
    fail "cannot extract real BIOS isolinux.cfg from ISO"
  xorriso -osirrox on -indev "$iso" -extract /EFI/BOOT/grub.cfg "$tmp/uefi.cfg" >/dev/null 2>&1 ||
    fail "cannot extract real EFI grub.cfg from ISO"
  grep -Eq '^DEFAULT[[:space:]]+boot([[:space:]]|$)' "$tmp/bios.cfg" ||
    fail "BIOS generic entry is not default"
  awk '
    $1=="LABEL" && $2=="boot" {generic=1; dell=0; next}
    $1=="LABEL" && $2=="boot-dell-internal-keyboard-off" {dell=1; generic=0; found_dell=1; next}
    $1=="LABEL" {generic=0; dell=0}
    generic && $1=="APPEND" && $0 !~ /i8042\.nokbd/ {generic_ok=1}
    dell && $1=="APPEND" && $0 ~ /i8042\.nokbd/ {dell_ok=1}
    END {exit !(found_dell && generic_ok && dell_ok)}
  ' "$tmp/bios.cfg" || fail "BIOS ISO lacks distinct generic and Dell kernel command lines"
  # NixOS' pinned iso-image.nix emits the generic installer menuentry
  # first, followed by the explicitly named Dell specialisation entry.
  # Match each Linux line to its *selectable menuentry*, rather than
  # accepting unrelated kernel lines in a nested submenu (QA gap).
  if grep -Eq '^[[:space:]]*set[[:space:]]+default[[:space:]]*=' "$tmp/uefi.cfg"; then
    grep -Eq '^[[:space:]]*set[[:space:]]+default[[:space:]]*=[[:space:]]*"?0"?[[:space:]]*
fi

echo "PASS: generic default preserves keyboards; Dell-only i8042.nokbd evaluated and BIOS/EFI verified"
 "$tmp/uefi.cfg" ||
      fail "EFI menu overrides the generic first/default entry"
  fi
  awk '
    /^[[:space:]]*menuentry[[:space:]]/ && /--class installer/ {
      entry++
      if (entry == 1) {
        if ($0 ~ /Dell internal keyboard OFF/) bad=1
        generic_menu=1
      } else if (entry == 2) {
        if ($0 !~ /Dell internal keyboard OFF \(USB required\)/) bad=1
        dell_menu=1
      }
      next
    }
    entry == 1 && /^[[:space:]]*linux[[:space:]]/ && /init=/ {
      if ($0 ~ /i8042\.nokbd/) bad=1
      else generic_args=1
    }
    entry == 2 && /^[[:space:]]*linux[[:space:]]/ && /init=/ {
      if ($0 !~ /i8042\.nokbd/) bad=1
      else dell_args=1
    }
    END {exit !(generic_menu && dell_menu && generic_args && dell_args && !bad)}
  ' "$tmp/uefi.cfg" || fail "EFI ISO lacks correctly labelled generic-default and Dell-only boot entries"
fi

echo "PASS: generic default preserves keyboards; Dell-only i8042.nokbd evaluated and BIOS/EFI verified"
