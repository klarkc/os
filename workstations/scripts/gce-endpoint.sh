#!/usr/bin/env bash
# Discover the current ephemeral public IP and authenticated WireGuard
# server public key from the owner's GCE instance, not from DDNS.
# Only a compute.readonly OAuth grant is persisted on the trusted USB.
set -euo pipefail

PROJECT="${SOLO_GCE_PROJECT:-argon-surf-472319-b0}"
ZONE="${SOLO_GCE_ZONE:-southamerica-east1-b}"
INSTANCE="${SOLO_GCE_INSTANCE:-solo-workstation}"
ADC="${HOME}/.config/gcloud/application_default_credentials.json"
STATE_TOOL="${SOLO_STATE_TOOL:-/run/current-system/sw/bin/solo-client-state}"
SCOPE="https://www.googleapis.com/auth/compute.readonly"

# A pure parser exposed for offline CI: never contacts Google or reads secrets.
# Output is one TAB-separated record: ephemeral IPv4, WG public key.
parse() {
  local record ip key octet
  record="$(jq -er '
    if .status != "RUNNING" then error("GCE instance is not running") else
      ([.networkInterfaces[]?.accessConfigs[]?.natIP | select(type == "string")][0]) as $ip
      | ([.metadata.items[]? | select(.key == "solo-wg-server-public-key") | .value][0]) as $key
      | if ($ip | type) == "string" and ($key | type) == "string"
          then "\($ip)\t\($key)"
          else error("GCE IPv4 or solo-wg-server-public-key metadata is missing")
        end
    end
  ')" || return 1

  IFS=$'\t' read -r ip key <<< "$record"
  # Validate before passing either value to the privileged wg helper.
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local -a octets
  IFS=. read -r -a octets <<< "$ip"
  [[ "${#octets[@]}" -eq 4 ]] || return 1
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^(0|[1-9][0-9]{0,2})$ ]] || return 1
    (( 10#$octet <= 255 )) || return 1
  done
  [[ "$key" =~ ^[a-zA-Z0-9+/]{43}=$ ]] || return 1
  [[ "$(printf '%s' "$key" | base64 --decode | wc -c)" -eq 32 ]] || return 1
  printf '%s\t%s\n' "$ip" "$key"
}

login() {
  if ! sudo -n "$STATE_TOOL" is-ready; then
    echo "Refusing OAuth bootstrap without a mounted Ventoy USB." >&2
    return 1
  fi
  if [[ -s "$ADC" ]]; then
    echo "Google Compute readonly authorization is already present."
    return 0
  fi
  echo "Authorize GCE instance discovery using your Google account."
  echo "Open the printed URL on another trusted device and enter its authorization code here."
  echo "This grant will be stored UNENCRYPTED on the trusted Ventoy USB."
  umask 077
  mkdir -p "$(dirname "$ADC")"
  gcloud auth application-default login \
    --no-launch-browser \
    --disable-quota-project \
    --scopes="$SCOPE"
  if ! [[ -s "$ADC" ]]; then
    echo "Google authorization did not create ADC credentials." >&2
    return 1
  fi
  sudo -n "$STATE_TOOL" save
}

resolve() {
  if ! [[ -s "$ADC" ]]; then
    echo "No GCE readonly credential. Run: solo-gce-endpoint login" >&2
    return 1
  fi

  local token
  if ! token="$(gcloud auth application-default print-access-token 2>/dev/null)" || [[ -z "$token" ]]; then
    echo "Unable to refresh GCE OAuth token. Re-authorize if the grant was revoked." >&2
    return 1
  fi

  # A fixed Google API origin; the user token never enters an external DDNS.
  # Curl's config through stdin also keeps the bearer token out of process argv.
  local uri="https://compute.googleapis.com/compute/v1/projects/${PROJECT}/zones/${ZONE}/instances/${INSTANCE}?fields=status%2CnetworkInterfaces(accessConfigs(natIP))%2Cmetadata(items(key%2Cvalue))"
  curl --fail --silent --show-error --connect-timeout 8 --max-time 20 \
    --retry 1 --config - <<CURL_CONFIG | parse
url = "$uri"
header = "Authorization: Bearer $token"
header = "Accept: application/json"
CURL_CONFIG
}

case "${1:-}" in
  login) login ;;
  resolve) resolve ;;
  parse) parse ;;
  has-credentials) [[ -s "$ADC" ]] ;;
  *)
    echo "Usage: solo-gce-endpoint {login|resolve|parse|has-credentials}" >&2
    exit 2
    ;;
esac
