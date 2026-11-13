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
diagnostic_fixture="$(mktemp -d)"
trap 'rm -f "$mock_loginctl"; rm -rf "$diagnostic_fixture"' EXIT
cat > "$mock_loginctl" <<'MOCK'
#!/bin/sh
[ "${LPKLARKC_TEST_LOGINCTL_FAIL:-0}" != "1" ] || exit 1
if [ "$1" = "show-seat" ]; then
  [ "${LPKLARKC_TEST_SEAT_FAIL:-0}" != "1" ] || exit 1
  [ "${LPKLARKC_TEST_SEAT_EMPTY:-0}" = "1" ] ||
    printf 'ActiveSession=%s\n' "${LPKLARKC_TEST_SEAT_ACTIVE_SESSION-1}"
  if [ "${LPKLARKC_TEST_DUPLICATE_SEAT:-0}" = "1" ]; then
    printf 'ActiveSession=99\n'
  fi
  exit 0
fi
if [ "${LPKLARKC_TEST_EMPTY_OUTPUT:-0}" = "1" ]; then
  exit 0
fi
if [ "${LPKLARKC_TEST_OMIT_ID:-0}" != "1" ]; then
  printf 'Id=%s\n' "${LPKLARKC_TEST_SESSION_ID-1}"
fi
if [ "${LPKLARKC_TEST_DUPLICATE_ID:-0}" = "1" ]; then
  printf 'Id=99\n'
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


# This read-only pre-startx check does not change the tty1 launch decision.
prestart_equal="$(LPKLARKC_LOGINCTL_BIN="$mock_loginctl" LPKLARKC_TEST_SESSION_ID=7 LPKLARKC_TEST_SEAT_ACTIVE_SESSION=7 bash scripts/thin-client.sh --check-xorg-prestart 2>&1)"
if [[ "$prestart_equal" != *'phase=manual self=7 active=yes vt=1 seat0=7 match=MESMA_SESSAO'* ]]; then
  echo 'FAIL: prestart matching owner observation missing' >&2; exit 1
fi
prestart_diff="$(LPKLARKC_LOGINCTL_BIN="$mock_loginctl" LPKLARKC_TEST_SESSION_ID=7 LPKLARKC_TEST_SEAT_ACTIVE_SESSION=8 bash scripts/thin-client.sh --check-xorg-prestart 2>&1)"
if [[ "$prestart_diff" != *'self=7 active=yes vt=1 seat0=8 match=DIVERGENTE'* ]]; then
  echo 'FAIL: prestart differing seat owner was not reported' >&2; exit 1
fi
prestart_missing="$(LPKLARKC_LOGINCTL_BIN="$mock_loginctl" LPKLARKC_TEST_SEAT_FAIL=1 bash scripts/thin-client.sh --check-xorg-prestart 2>&1)"
if [[ "$prestart_missing" != *'seat0=? match=INDETERMINADA'* ]]; then
  echo 'FAIL: unavailable seat0 query was falsely trusted' >&2; exit 1
fi
prestart_dup_id="$(LPKLARKC_LOGINCTL_BIN="$mock_loginctl" LPKLARKC_TEST_DUPLICATE_ID=1 bash scripts/thin-client.sh --check-xorg-prestart 2>&1)"
if [[ "$prestart_dup_id" != *'self=?'* || "$prestart_dup_id" != *'match=INDETERMINADA'* ]]; then
  echo 'FAIL: duplicate session ids were falsely trusted' >&2; exit 1
fi
prestart_dup_seat="$(LPKLARKC_LOGINCTL_BIN="$mock_loginctl" LPKLARKC_TEST_DUPLICATE_SEAT=1 bash scripts/thin-client.sh --check-xorg-prestart 2>&1)"
if [[ "$prestart_dup_seat" != *'seat0=? match=INDETERMINADA'* ]]; then
  echo 'FAIL: duplicate seat owners were falsely trusted' >&2; exit 1
fi
prestart_no_id="$(LPKLARKC_LOGINCTL_BIN="$mock_loginctl" LPKLARKC_TEST_OMIT_ID=1 bash scripts/thin-client.sh --check-xorg-prestart 2>&1)"
if [[ "$prestart_no_id" != *'self=?'* || "$prestart_no_id" != *'match=INDETERMINADA'* ]]; then
  echo 'FAIL: missing session id was falsely trusted' >&2; exit 1
fi

# One-command Dell field diagnostic: read-only card1 and logind/Xorg signatures,
# runnable from tty2 without requiring root, an X server or a physical GPU.
mkdir -p "$diagnostic_fixture/dev" "$diagnostic_fixture/sys/card1/device" \
  "$diagnostic_fixture/drivers/i915" "$diagnostic_fixture/empty"
touch "$diagnostic_fixture/dev/card1"
printf '226:1\n' > "$diagnostic_fixture/sys/card1/dev"
ln -s "$diagnostic_fixture/drivers/i915" \
  "$diagnostic_fixture/sys/card1/device/driver"
printf '%s\n' \
  '(II) xfree86: Adding drm device (/dev/dri/card1)' \
  '(II) systemd-logind: got fd for /dev/dri/card1 226:1 fd 11 paused 1' \
  '(EE) Screen 0 deleted because of no matching config section' \
  '(EE) no screens found' > "$diagnostic_fixture/Xorg.0.log"
diagnostic_output="$(
  LPKLARKC_LOGINCTL_BIN="$mock_loginctl" \
  LPKLARKC_TEST_ACTIVE=yes LPKLARKC_TEST_VTNR=2 \
  LPKLARKC_DIAG_DRM_DIR="$diagnostic_fixture/dev" \
  LPKLARKC_DIAG_SYS_DRM_DIR="$diagnostic_fixture/sys" \
  LPKLARKC_DIAG_XORG_LOG="$diagnostic_fixture/Xorg.0.log" \
  bash scripts/thin-client.sh --diagnose-xorg
)"
for expected in \
  'card1 major_minor=226:1 driver=i915' \
  'got fd for /dev/dri/card1 226:1 fd 11 paused 1' \
  'Screen 0 deleted because of no matching config section' \
  'no screens found' \
  'Correlacao self/seat0: MESMA_SESSAO' \
  'nao prova a sessao no instante'; do
  if [[ "$diagnostic_output" != *"$expected"* ]]; then
    printf 'FAIL: read-only Dell diagnostic did not report %s\n' "$expected" >&2
    exit 1
  fi
done
# A different seat owner is evidence, not a hard Xorg/VT gate:
# invoking from tty2 cannot reconstruct the original paused logind fd.
diagnostic_mismatch="$(
  LPKLARKC_LOGINCTL_BIN="$mock_loginctl" \
  LPKLARKC_TEST_SESSION_ID=7 LPKLARKC_TEST_SEAT_ACTIVE_SESSION=8 \
  LPKLARKC_DIAG_DRM_DIR="$diagnostic_fixture/dev" \
  LPKLARKC_DIAG_SYS_DRM_DIR="$diagnostic_fixture/sys" \
  LPKLARKC_DIAG_XORG_LOG="$diagnostic_fixture/Xorg.0.log" \
  bash scripts/thin-client.sh --diagnose-xorg
)"
if [[ "$diagnostic_mismatch" != *'Correlacao self/seat0: DIVERGENTE'* ]]; then
  echo 'FAIL: diagnostic did not show conflicting self and active seat sessions' >&2
  exit 1
fi
diagnostic_unknown="$(
  LPKLARKC_LOGINCTL_BIN="$mock_loginctl" \
  LPKLARKC_TEST_SEAT_FAIL=1 \
  LPKLARKC_DIAG_DRM_DIR="$diagnostic_fixture/dev" \
  LPKLARKC_DIAG_SYS_DRM_DIR="$diagnostic_fixture/sys" \
  LPKLARKC_DIAG_XORG_LOG="$diagnostic_fixture/Xorg.0.log" \
  bash scripts/thin-client.sh --diagnose-xorg
)"
if [[ "$diagnostic_unknown" != *'consulta seat0 indisponivel'* ||
      "$diagnostic_unknown" != *'Correlacao self/seat0: INDETERMINADA'* ]]; then
  echo 'FAIL: diagnostic inferred seat ownership from failed logind read' >&2
  exit 1
fi
diagnostic_missing_id="$(
  LPKLARKC_LOGINCTL_BIN="$mock_loginctl" \
  LPKLARKC_TEST_OMIT_ID=1 \
  LPKLARKC_DIAG_DRM_DIR="$diagnostic_fixture/dev" \
  LPKLARKC_DIAG_SYS_DRM_DIR="$diagnostic_fixture/sys" \
  LPKLARKC_DIAG_XORG_LOG="$diagnostic_fixture/Xorg.0.log" \
  bash scripts/thin-client.sh --diagnose-xorg
)"
if [[ "$diagnostic_missing_id" != *'Correlacao self/seat0: INDETERMINADA'* ]]; then
  echo 'FAIL: diagnostic inferred missing current session ID' >&2
  exit 1
fi

# Duplicate logind properties must be marked ambiguous, even if an
# otherwise well-formed value was present earlier in the same response.
diagnostic_duplicate_id="$(
  LPKLARKC_LOGINCTL_BIN="$mock_loginctl" \
  LPKLARKC_TEST_DUPLICATE_ID=1 \
  LPKLARKC_DIAG_DRM_DIR="$diagnostic_fixture/dev" \
  LPKLARKC_DIAG_SYS_DRM_DIR="$diagnostic_fixture/sys" \
  LPKLARKC_DIAG_XORG_LOG="$diagnostic_fixture/Xorg.0.log" \
  bash scripts/thin-client.sh --diagnose-xorg
)"
if [[ "$diagnostic_duplicate_id" != *'Correlacao self/seat0: INDETERMINADA'* ]]; then
  echo 'FAIL: recovery diagnostic trusted a duplicate Id property' >&2
  exit 1
fi
diagnostic_duplicate_seat="$(
  LPKLARKC_LOGINCTL_BIN="$mock_loginctl" \
  LPKLARKC_TEST_DUPLICATE_SEAT=1 \
  LPKLARKC_DIAG_DRM_DIR="$diagnostic_fixture/dev" \
  LPKLARKC_DIAG_SYS_DRM_DIR="$diagnostic_fixture/sys" \
  LPKLARKC_DIAG_XORG_LOG="$diagnostic_fixture/Xorg.0.log" \
  bash scripts/thin-client.sh --diagnose-xorg
)"
if [[ "$diagnostic_duplicate_seat" != *'Correlacao self/seat0: INDETERMINADA'* ]]; then
  echo 'FAIL: recovery diagnostic trusted a duplicate seat0 ActiveSession' >&2
  exit 1
fi

diagnostic_empty="$(
  LPKLARKC_LOGINCTL_BIN="$mock_loginctl" \
  LPKLARKC_DIAG_DRM_DIR="$diagnostic_fixture/empty" \
  LPKLARKC_DIAG_SYS_DRM_DIR="$diagnostic_fixture/sys" \
  LPKLARKC_DIAG_XORG_LOG="$diagnostic_fixture/missing.log" \
  bash scripts/thin-client.sh --diagnose-xorg
)"
if [[ "$diagnostic_empty" != *'nenhum cardN presente'* ||
      "$diagnostic_empty" != *'Xorg.0.log indisponivel'* ]]; then
  echo 'FAIL: read-only diagnostic did not tolerate absent DRM/log files' >&2
  exit 1
fi

echo 'PASS: generic live-ISO hardware, firmware, GPU/Xorg fallback and BIOS/UEFI evaluation and rootless logind seat guards'
