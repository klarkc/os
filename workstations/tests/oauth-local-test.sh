#!/usr/bin/env bash
# Purely offline, non-root regression for the Dell's local OAuth flow.
# No real browser, credentials, Google account, USB disk or cloud API calls.
set -euo pipefail
iap="${1:?gce-iap.sh required}"
session="${2:?oauth-session.sh required}"
browser="${3:?oauth-browser.sh required}"
dir="$(mktemp -d)"
trap 'rm -rf -- "$dir"' EXIT
mkdir -p "$dir/run" "$dir/config"
# Repository sources need not have executable mode; test installed wrappers.
install -m 0700 -- "$iap" "$dir/iap"
install -m 0700 -- "$session" "$dir/session"
install -m 0700 -- "$browser" "$dir/browser"
iap="$dir/iap"
session="$dir/session"
browser="$dir/browser"
cat > "$dir/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "-n" && "$3" == "is-ready" || "$1" == "-n" && "$3" == "save" ]] || exit 9
shift
"$@"
EOF
cat > "$dir/state" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
 is-ready) [[ ! -e "$CI_DIR/usb-denied" ]] ;;
 save) [[ ! -e "$CI_DIR/usb-denied" ]] && touch "$CI_DIR/saved" ;;
 *) exit 9 ;;
esac
EOF
cat > "$dir/wm" <<'EOF'
#!/usr/bin/env bash
exec sleep 60
EOF
cat > "$dir/firefox" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ! -e "$CI_DIR/browser-failed" ]] || exit 44
[[ "$1" == "--no-remote" && "$2" == "--new-instance" && "$3" == "--profile" ]] || exit 8
[[ -d "$4" && "$5" == https://accounts.google.com/* ]] || exit 8
printf '%s\n' "$5" > "$CI_DIR/url-opened"
printf '%s\n' "$4" > "$CI_DIR/profile-used"
EOF
cat > "$dir/gcloud" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
 "auth login")
   [[ " $* " == *" --launch-browser "* ]] || exit 11
   [[ " $* " == *" --project=argon-surf-472319-b0 "* ]] || exit 11
   [[ ! -e "$CI_DIR/login-cancelled" ]] || exit 17
   "$BROWSER" 'https://accounts.google.com/o/oauth2/auth?mock=1'
   mkdir -p "$CLOUDSDK_CONFIG/configurations"
   printf 'mock-sqlite-fixture\n' > "$CLOUDSDK_CONFIG/credentials.db"
   printf 'account = ci@example.invalid\n' > "$CLOUDSDK_CONFIG/configurations/config_default"
   ;;
 "auth print-access-token")
   [[ -s "$CLOUDSDK_CONFIG/credentials.db" ]] || exit 18
   printf 'ci-never-real-token\n'
   ;;
 *) exit 99 ;;
esac
EOF
chmod 0700 "$dir/sudo" "$dir/state" "$dir/wm" "$dir/firefox" "$dir/gcloud"
export CI_DIR="$dir"
export LPKLARKC_SUDO_BIN="$dir/sudo"
export LPKLARKC_STATE_TOOL="$dir/state"
export LPKLARKC_GCLOUD_BIN="$dir/gcloud"
export LPKLARKC_GCLOUD_CONFIG="$dir/config"
export LPKLARKC_OAUTH_IAP_TOOL="$iap"
export LPKLARKC_OAUTH_BROWSER_BIN="$dir/firefox"
export LPKLARKC_OAUTH_WM_BIN="$dir/wm"
export LPKLARKC_OAUTH_HELPER_BIN="$browser"
export XDG_RUNTIME_DIR="$dir/run"
export DISPLAY=:99
# Real gcloud preflight cannot run from tty without a graphical session.
if env -u DISPLAY bash "$iap" login >/dev/null 2>&1; then
 echo "FAIL: tty-only login accepted" >&2; exit 1
fi
bash "$session"
test -s "$dir/url-opened"
test -e "$dir/saved"
test -s "$dir/config/credentials.db"
test -z "$(find "$dir/run" -mindepth 1 -print -quit)"
# Permissions are checked BEFORE Google login and after each retry.
rm -f "$dir/saved" "$dir/url-opened"
touch "$dir/usb-denied"
if bash "$session" >/dev/null 2>&1; then
 echo "FAIL: root-only USB rejection accepted" >&2; exit 1
fi
test ! -e "$dir/saved"
test ! -e "$dir/url-opened"
rm -f "$dir/usb-denied"
touch "$dir/login-cancelled"
if bash "$session" >/dev/null 2>&1; then
 echo "FAIL: cancelled login accepted" >&2; exit 1
fi
test ! -e "$dir/saved"
rm -f "$dir/login-cancelled"
touch "$dir/browser-failed"
if bash "$session" >/dev/null 2>&1; then
 echo "FAIL: missing local browser accepted" >&2; exit 1
fi
test ! -e "$dir/saved"
test -z "$(find "$dir/run" -mindepth 1 -print -quit)"
echo "PASS: local OAuth browser, USB gate, cancel/failure and RAM cleanup (offline mocks)"
