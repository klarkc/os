#!/usr/bin/env bash
# Dell 2026-11-02: Xorg may be alive while the first-boot OAuth client exits.
# Reproduce without Google accounts, real tokens, disks, or a live cloud VM.
# Deliberately exercise a real X11 server, not merely DISPLAY=:99.
set -euo pipefail

session_source="$1"
browser_source="$2"
[[ "$(id -u)" -ne 0 ]] || { echo "Run as an unprivileged CI user" >&2; exit 2; }
command -v Xvfb >/dev/null
command -v dbus-run-session >/dev/null
command -v dbus-send >/dev/null

root="$(mktemp -d)"
xpid=""
cleanup() {
  [[ -z "$xpid" ]] || kill "$xpid" 2>/dev/null || true
  rm -rf -- "$root"
}
trap cleanup EXIT
mkdir -m 700 "$root/run" "$root/fixtures"
install -m 700 "$session_source" "$root/fixtures/session"
install -m 700 "$browser_source" "$root/fixtures/browser"

cat > "$root/fixtures/wm" <<'MOCK'
#!/usr/bin/env bash
exec sleep 60
MOCK

cat > "$root/fixtures/firefox" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "--no-remote" && "$2" == "--new-instance" &&
   "$3" == "--profile" && -d "$4" ]] || exit 45
[[ "$5" == https://accounts.google.com/* ]] || exit 46
[[ -S /tmp/.X11-unix/X187 ]] || { echo "X11 socket unavailable" >&2; exit 47; }
[[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] ||
  { echo "Browser has no active D-Bus session" >&2; exit 48; }
dbus-send --session --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.ListNames >/dev/null
printf 'browser-opened\n' > "$TEST_BROWSER_MARKER"
MOCK

cat > "$root/fixtures/iap" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == login ]] || exit 49
"$BROWSER" 'https://accounts.google.com/o/oauth2/auth?mock=1'
test -s "$TEST_BROWSER_MARKER"
MOCK

chmod 700 "$root/fixtures/"*
Xvfb :187 -screen 0 1024x768x24 -nolisten tcp > "$root/xvfb.log" 2>&1 &
xpid=$!
for n in {1..30}; do
  [[ -S /tmp/.X11-unix/X187 ]] && break
  sleep .1
done
[[ -S /tmp/.X11-unix/X187 ]] || { cat "$root/xvfb.log"; exit 2; }

export DISPLAY=:187
export LPKLARKC_OAUTH_IAP_TOOL="$root/fixtures/iap"
export LPKLARKC_OAUTH_BROWSER_BIN="$root/fixtures/firefox"
export LPKLARKC_OAUTH_WM_BIN="$root/fixtures/wm"
export LPKLARKC_OAUTH_HELPER_BIN="$root/fixtures/browser"
export LPKLARKC_OAUTH_DBUS_BIN="$(command -v dbus-run-session)"
export TEST_BROWSER_MARKER="$root/browser-opened"

# Security: no session on a missing DISPLAY.
if env -u DISPLAY bash "$root/fixtures/session" >"$root/no-display.log" 2>&1; then
  echo "FAIL: missing DISPLAY was accepted" >&2
  exit 1
fi

# Reproduces the early-exit scenario on a rootless first boot: Xorg is alive,
# but logind/XDG_RUNTIME_DIR points to an unavailable directory.
export XDG_RUNTIME_DIR="$root/missing-runtime"
if ! env -u DBUS_SESSION_BUS_ADDRESS timeout 15 bash "$root/fixtures/session" >"$root/runtime.log" 2>&1; then
  echo "FAIL: OAuth terminated before launching browser with live Xorg and stale XDG_RUNTIME_DIR" >&2
  cat "$root/runtime.log" >&2
  exit 1
fi
test -s "$TEST_BROWSER_MARKER"
rm -f "$TEST_BROWSER_MARKER"

# Independently verify the browser gets a working session bus, even when the
# XDG runtime directory exists. The old mocked OAuth test never checked this.
export XDG_RUNTIME_DIR="$root/run"
if ! env -u DBUS_SESSION_BUS_ADDRESS timeout 15 bash "$root/fixtures/session" >"$root/dbus.log" 2>&1; then
  echo "FAIL: browser launched without a working session D-Bus" >&2
  cat "$root/dbus.log" >&2
  exit 1
fi
test -s "$TEST_BROWSER_MARKER"
echo "PASS: rootless X11 OAuth startup, stale runtime recovery, browser D-Bus and fail-closed DISPLAY"
