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
    printf 'FAIL: generic Xorg KMS driver %s not available\n' "$driver" >&2
    exit 1
  fi
}
reject_legacy_xdriver() {
  local driver="$1"
  if nix_opt services.xserver.videoDrivers |
      jq -e --arg driver "$driver" 'index($driver) != null' >/dev/null; then
    printf 'FAIL: incompatible legacy Xorg DDX %s was reintroduced\n' "$driver" >&2
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

# Require the production Xorg DDX path that actually loaded with real
# QEMU DRM/KMS (CI 42054451544), not optional DDX that failed to dlopen.
# This asserts the Xorg module list only; generic Intel/Nouveau kernel
# DRM/KMS and redistributable firmware remain governed by the all-hardware
# profile and must still pass the real QEMU + physical-release gates.
for driver in modesetting amdgpu; do
  require_xdriver "$driver"
done
for driver in nouveau intel vesa; do
  reject_legacy_xdriver "$driver"
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

# BROKER-013 physical i915/card1 logind paused-fd regression.
# The check is read-only, never hardcodes /dev/dri/card0 or switches VTs.
# It must refuse an explicitly inactive tty1 or wrong VT while allowing
# an active tty1 and a transiently unqueryable logind to reach existing Xorg.
mock_loginctl="$(mktemp)"
trap 'rm -f "$mock_loginctl"' EXIT
cat > "$mock_loginctl" <<'MOCK'
#!/bin/sh
[ "${LPKLARKC_TEST_LOGINCTL_FAIL:-0}" != "1" ] || exit 1
if [ "${LPKLARKC_TEST_EMPTY_OUTPUT:-0}" = "1" ]; then
  exit 0
fi
if [ "${LPKLARKC_TEST_OMIT_ACTIVE:-0}" != "1" ]; then
  printf 'Active=%s\n' "${LPKLARKC_TEST_ACTIVE-yes}"
fi
if [ "${LPKLARKC_TEST_DUPLICATE_ACTIVE:-0}" = "1" ]; then
  printf 'Active=yes\n'
fi
if [ "${LPKLARKC_TEST_OMIT_VTNR:-0}" != "1" ]; then
  printf 'VTNr=%s\n' "${LPKLARKC_TEST_VTNR-1}"
fi
exit 0
MOCK
chmod +x "$mock_loginctl"
if ! LPKLARKC_LOGINCTL_BIN="$mock_loginctl" LPKLARKC_TEST_ACTIVE=yes LPKLARKC_TEST_VTNR=1 bash scripts/thin-client.sh --check-xorg-seat; then
  echo 'FAIL: active tty1 logind session blocked' >&2
  exit 1
fi
if LPKLARKC_LOGINCTL_BIN="$mock_loginctl" LPKLARKC_TEST_ACTIVE=no LPKLARKC_TEST_VTNR=1 bash scripts/thin-client.sh --check-xorg-seat >/dev/null 2>&1; then
  echo 'FAIL: inactive tty1 was allowed to launch rootless Xorg' >&2
  exit 1
fi
if LPKLARKC_LOGINCTL_BIN="$mock_loginctl" LPKLARKC_TEST_ACTIVE=yes LPKLARKC_TEST_VTNR=2 bash scripts/thin-client.sh --check-xorg-seat >/dev/null 2>&1; then
  echo 'FAIL: wrong VT was allowed to launch vt1 Xorg' >&2
  exit 1
fi
if LPKLARKC_LOGINCTL_BIN="$mock_loginctl" LPKLARKC_TEST_OMIT_ACTIVE=1 bash scripts/thin-client.sh --check-xorg-seat >/dev/null 2>&1; then
  echo 'FAIL: successful logind reply missing Active was allowed' >&2
  exit 1
fi
if LPKLARKC_LOGINCTL_BIN="$mock_loginctl" LPKLARKC_TEST_OMIT_VTNR=1 bash scripts/thin-client.sh --check-xorg-seat >/dev/null 2>&1; then
  echo 'FAIL: successful logind reply missing VTNr was allowed' >&2
  exit 1
fi
if LPKLARKC_LOGINCTL_BIN="$mock_loginctl" LPKLARKC_TEST_EMPTY_OUTPUT=1 bash scripts/thin-client.sh --check-xorg-seat >/dev/null 2>&1; then
  echo 'FAIL: successful empty logind reply was allowed' >&2
  exit 1
fi
if LPKLARKC_LOGINCTL_BIN="$mock_loginctl" LPKLARKC_TEST_ACTIVE=unknown bash scripts/thin-client.sh --check-xorg-seat >/dev/null 2>&1; then
  echo 'FAIL: unknown successful logind Active value was allowed' >&2
  exit 1
fi
if LPKLARKC_LOGINCTL_BIN="$mock_loginctl" LPKLARKC_TEST_ACTIVE= bash scripts/thin-client.sh --check-xorg-seat >/dev/null 2>&1; then
  echo 'FAIL: empty successful logind Active value was allowed' >&2
  exit 1
fi
if LPKLARKC_LOGINCTL_BIN="$mock_loginctl" LPKLARKC_TEST_VTNR= bash scripts/thin-client.sh --check-xorg-seat >/dev/null 2>&1; then
  echo 'FAIL: empty successful logind VTNr was allowed' >&2
  exit 1
fi
if LPKLARKC_LOGINCTL_BIN="$mock_loginctl" LPKLARKC_TEST_DUPLICATE_ACTIVE=1 bash scripts/thin-client.sh --check-xorg-seat >/dev/null 2>&1; then
  echo 'FAIL: duplicate logind Active property was allowed' >&2
  exit 1
fi
if ! LPKLARKC_LOGINCTL_BIN="$mock_loginctl" LPKLARKC_TEST_LOGINCTL_FAIL=1 bash scripts/thin-client.sh --check-xorg-seat; then
  echo 'FAIL: transient logind read error deadlocked kiosk' >&2
  exit 1
fi

echo 'PASS: generic live-ISO hardware, firmware, GPU/Xorg fallback and BIOS/UEFI evaluation and rootless logind seat guards'
