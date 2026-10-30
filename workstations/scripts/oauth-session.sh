#!/usr/bin/env bash
# Temporary local X11 browser session. Called by rootless startx on the Dell.
# Firefox profile and XDG state live exclusively in RAM, not on USB/HDD.
set -euo pipefail
umask 077
iap="${LPKLARKC_OAUTH_IAP_TOOL:-/run/current-system/sw/bin/lpklarkc-iap}"
firefox="${LPKLARKC_OAUTH_BROWSER_BIN:-}"
wm="${LPKLARKC_OAUTH_WM_BIN:-}"
browser_helper="${LPKLARKC_OAUTH_HELPER_BIN:-/run/current-system/sw/bin/lpklarkc-oauth-browser}"
if [[ -z "${DISPLAY:-}" || "$(id -u)" -eq 0 ]]; then
  echo "OAuth requires a rootless local graphical Xorg session." >&2
  exit 4
fi
if [[ ! -x "$iap" || ! -x "$firefox" || ! -x "$wm" || ! -x "$browser_helper" ]]; then
  echo "Local OAuth components missing; browser/WM/IAP not installed." >&2
  exit 4
fi
runtime="${XDG_RUNTIME_DIR:-/tmp}"
if [[ ! -d "$runtime" || ! -w "$runtime" ]]; then
  echo "No writable RAM runtime for disposable OAuth browser profile." >&2
  exit 4
fi
session_dir="$(mktemp -d "$runtime/lpklarkc-oauth.XXXXXXXX")"
chmod 0700 "$session_dir"
wm_pid=""
cleanup() {
  if [[ -n "$wm_pid" ]]; then
    kill "$wm_pid" 2>/dev/null || true
    wait "$wm_pid" 2>/dev/null || true
  fi
  rm -rf -- "$session_dir"
}
trap cleanup EXIT
export LPKLARKC_OAUTH_PROFILE="$session_dir/profile"
export LPKLARKC_OAUTH_BROWSER_PROOF="$session_dir/browser-opened"
export LPKLARKC_OAUTH_BROWSER_BIN="$firefox"
export BROWSER="$browser_helper"
export XDG_CONFIG_HOME="$session_dir/config"
export XDG_CACHE_HOME="$session_dir/cache"
export XDG_DATA_HOME="$session_dir/data"
mkdir -m 0700 "$LPKLARKC_OAUTH_PROFILE" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"

"$wm" --sm-disable >/dev/null 2>&1 &
wm_pid=$!
sleep 1
if ! kill -0 "$wm_pid" 2>/dev/null; then
  echo "Local window manager failed to start." >&2
  exit 4
fi
echo "Abrindo o login Google no navegador deste Dell; nao use outro dispositivo."
if ! timeout --foreground 900 "$iap" login; then
  echo "OAuth local falhou/foi cancelado ou expirou; nenhum login foi confirmado." >&2
  exit 10
fi
if [[ ! -s "$LPKLARKC_OAUTH_BROWSER_PROOF" ]]; then
  echo "Google login returned without opening the local browser." >&2
  exit 10
fi
echo "OAuth local concluido; fechando navegador e retornando ao kiosk."
