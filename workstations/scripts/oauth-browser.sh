#!/usr/bin/env bash
# Private browser launcher for the one-time local Google CLI OAuth callback.
# Never persist Firefox profile, cookies or history to the Ventoy USB.
set -euo pipefail
umask 077
url="${1:-}"
profile="${LPKLARKC_OAUTH_PROFILE:-}"
proof="${LPKLARKC_OAUTH_BROWSER_PROOF:-}"
firefox="${LPKLARKC_OAUTH_BROWSER_BIN:-}"
if [[ -z "${DISPLAY:-}" || -z "$profile" || ! -d "$profile" ||
      -L "$profile" || -z "$proof" || ! -x "$firefox" ]]; then
  echo "Local OAuth browser unavailable (DISPLAY/profile/Firefox)." >&2
  exit 5
fi
# The CLI initiates HTTPS Google authorization. The localhost callback is
# handled by Firefox; it never needs to be opened by this helper.
case "$url" in
  https://*) ;;
  *) echo "Refusing a non-HTTPS OAuth browser URL." >&2; exit 6 ;;
esac
# This marker proves gcloud actually invoked the *local* BROWSER helper.
# Only the login result and token validation can establish authentication.
printf 'browser-invoked\n' > "$proof"
exec "$firefox" --no-remote --new-instance --profile "$profile" "$url"
