#!/usr/bin/env bash
# Runs via OS Login SSH + IAP, as root (sudo -n). This is NEVER included
# in the NixOS image or metadata. The only credential arrives on stdin.
set -euo pipefail
umask 077
user=wsklarkcci
marker="/home/$user/.wsklarkc-e2e-marker"
mode="${1:-}"

[[ "$(id -u)" -eq 0 ]] || { echo "FAIL: guest E2E needs sudo" >&2; exit 2; }
[[ "$(hostname)" == wsklarkc ]] || { echo "FAIL: wrong guest hostname" >&2; exit 2; }
case "$mode" in
  setup)
    IFS= read -r password
    [[ ${#password} -ge 24 && "$password" =~ ^[a-f0-9]+$ ]] || {
      echo "FAIL: invalid temporary password input" >&2
      exit 2
    }
    if id "$user" >/dev/null 2>&1; then
      test -f "$marker" || {
        echo "FAIL: existing test account has no expected persistence marker" >&2
        exit 1
      }
      echo "PASS: previously provisioned temporary account still exists"
    else
      useradd --create-home --shell /bin/bash "$user"
    fi
    printf '%s:%s\n' "$user" "$password" | chpasswd
    unset password
    if [[ ! -e "$marker" ]]; then
      printf '%s\n' 'wsklarkc-ci-persistence-verified-after-real-stop-start' > "$marker"
      chown "$user:users" "$marker"
      chmod 0600 "$marker"
    fi
    systemctl is-active --quiet xrdp.service xrdp-sesman.service || {
      echo "FAIL: XRDP services not active" >&2
      exit 1
    }
    if command -v nft >/dev/null 2>&1; then
      nft -nn list ruleset | grep -F '35.235.240.0/20' >/dev/null || {
        echo "FAIL: guest firewall missing IAP range" >&2
        exit 1
      }
    else
      echo "FAIL: nftables tool unavailable" >&2
      exit 1
    fi
    echo "PASS: temporary E2E RDP login is ready; no password logged"
    ;;
  verify)
    id "$user" >/dev/null
    test -f "$marker"
    grep -Fx 'wsklarkc-ci-persistence-verified-after-real-stop-start' "$marker" >/dev/null
    login_pid=""
    for _ in $(seq 1 30); do
      login_pid="$(pgrep -u "$user" -x xmonad | head -n 1 || true)"
      [[ -n "$login_pid" ]] && break
      sleep 2
    done
    [[ -n "$login_pid" ]] || {
      echo "FAIL: no authenticated user-owned XMonad process after RDP login" >&2
      exit 1
    }
    test -r "/proc/$login_pid/environ" || {
      echo "FAIL: cannot inspect XMonad process environment" >&2
      exit 1
    }
    tr '\0' '\n' <"/proc/$login_pid/environ" | grep -E '^DISPLAY=:[0-9]+' >/dev/null || {
      echo "FAIL: XMonad process has no real Xorg DISPLAY" >&2
      exit 1
    }
    echo "PASS: XRDP authenticated $user and launched XMonad in graphical DISPLAY"
    echo "PASS: marker persisted in the test account home"
    ;;
  marker)
    id "$user" >/dev/null
    test -f "$marker"
    grep -Fx 'wsklarkc-ci-persistence-verified-after-real-stop-start' "$marker" >/dev/null
    systemctl is-active --quiet xrdp.service xrdp-sesman.service
    echo "PASS: GCE stop/start retained guest HOME marker and XRDP services"
    ;;
  cleanup)
    # Never delete the actual developer account or HOME; this test's
    # disposable user is the only one eligible for removal.
    if id "$user" >/dev/null 2>&1; then
      loginctl terminate-user "$user" >/dev/null 2>&1 || true
      pkill -u "$user" >/dev/null 2>&1 || true
      userdel --remove "$user"
    fi
    echo "PASS: disposable E2E user and HOME deleted"
    ;;
  *)
    echo "Usage: gce-rdp-guest-e2e.sh {setup|verify|marker|cleanup}" >&2
    exit 2
    ;;
esac
