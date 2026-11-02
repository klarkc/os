#!/usr/bin/env bash
# Regression for Dell 2026-11-02 Xorg failure and generic live-ISO hardware.
# Actual Dell Xorg log:
#   open /dev/dri/card0: No such file or directory
#   Failed to load module "fbdev": undefined symbol: fbdevHWSave
#   no screens found
# A rootless startx can only succeed if the kernel has supported hardware,
# redistributable firmware, graphics libraries and a usable Xorg driver.
# This evaluates the PRODUCTION ISO config, not the simplified QEMU test node.
# It is a necessary hardware-support regression, NOT proof any laptop boots.
set -euo pipefail
cd "$(dirname "$0")/.."

nix_opt() {
  nix eval --json ".#nixosConfigurations.lpklarkc.config.$1"
}
require_true() {
  local v
  v="$(nix_opt "$1")"
  if [[ "$v" != true ]]; then
    printf 'FAIL: generic live ISO requires %s=true (actual %s)\n' "$1" "$v" >&2
    exit 1
  fi
}
require_xdriver() {
  local driver="$1"
  if ! nix_opt services.xserver.videoDrivers |
      jq -e --arg driver "$driver" 'index($driver) != null' >/dev/null; then
    printf 'FAIL: generic Xorg fallback driver %s not available\n' "$driver" >&2
    exit 1
  fi
}

# Previously forced OFF to shrink the Dell-only ISO; these are the
# configuration-specific preconditions missing in the Dell field failure.
require_true hardware.enableAllHardware
require_true hardware.enableRedistributableFirmware
require_true hardware.graphics.enable
require_true services.xserver.enable
require_true services.xserver.displayManager.startx.enable

# Modern KMS; AMD/Nouveau; old Intel integrated; BIOS framebuffer if DRM
# cannot make /dev/dri/card0. No claim this is a universal UEFI fallback.
for driver in modesetting amdgpu nouveau intel vesa; do
  require_xdriver "$driver"
done
# A generic live image must retain both legacy BIOS and EFI boot.
require_true isoImage.makeBiosBootable
require_true isoImage.makeEfiBootable
require_true isoImage.makeUsbBootable

# Eliminate the Dell-era curated firmware as the *only* device support.
# The image should use standard redistributable NixOS firmware collection.
if grep -Eq 'hardware\.enableAllHardware[[:space:]]*=[[:space:]]*false|hardware\.enableRedistributableFirmware[[:space:]]*=[[:space:]]*false|hardware\.graphics\.enable[[:space:]]*=[[:space:]]*lib\.mkForce[[:space:]]+false' \
    flake.nix thin-client.nix; then
  echo 'FAIL: device-specific hardware/graphics disables remain' >&2
  exit 1
fi

echo 'PASS: generic live-ISO hardware, firmware, GPU/Xorg fallback and BIOS/UEFI evaluation'
