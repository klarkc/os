#!/usr/bin/env bash
# Read-only production audit: requires the authenticated, authorized gcloud CLI.
# Never run with bash -x; no access tokens, policies or metadata are printed.
set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

project=argon-surf-472319-b0
zone=southamerica-east1-b
instance=solo-workstation
tag=solo-workstation-iap
iap_cidr=35.235.240.0/20
status=0

for tool in gcloud jq; do
  command -v "$tool" >/dev/null || { echo "FAIL: missing $tool" >&2; exit 2; }
done

tmp="$(mktemp -d)"
chmod 700 "$tmp"
trap 'rm -rf -- "$tmp"' EXIT

check() {
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $label"
  else
    echo "FAIL: $label" >&2
    status=1
  fi
}
label="IAP API enabled"
check bash -c 'gcloud services list --enabled --project="$1" --format="value(config.name)" | grep -Fx iap.googleapis.com' _ "$project"

# The VM does not exist until explicitly approved and provisioned.
if ! gcloud compute instances describe "$instance" --project="$project" --zone="$zone" --format=json >"$tmp/instance.json" 2>"$tmp/describe.err"; then
  echo "PENDING: instance $instance not present or instance.get unavailable" >&2
  exit 2
fi

label="CPU-only e2-highmem-4 configuration"
check jq -e '.machineType | endswith("/e2-highmem-4")' "$tmp/instance.json"
label="OS Login metadata enabled on instance"
check jq -e 'any(.metadata.items[]?; .key=="enable-oslogin" and (.value|ascii_downcase)=="true")' "$tmp/instance.json"
label="isolated IAP firewall target tag"
check jq -e --arg tag "$tag" '(.tags.items // []) | index($tag) != null' "$tmp/instance.json"

network="$(jq -r '.networkInterfaces[0].network // empty' "$tmp/instance.json")"
for port in 3389 22; do
  rule="solo-workstation-iap-$([ "$port" = 3389 ] && echo rdp || echo ssh)"
  if ! gcloud compute firewall-rules describe "$rule" --project="$project" --format=json >"$tmp/rule-$port.json" 2>"$tmp/rule-$port.err"; then
    echo "FAIL: missing VPC firewall rule for TCP $port" >&2
    status=1
    continue
  fi
  label="VPC rule $rule scoped to IAP CIDR, VM tag and only TCP $port"
  check jq -e --arg cidr "$iap_cidr" --arg network "$network" --arg tag "$tag" --arg port "$port" '
    .direction == "INGRESS" and (.disabled != true)
    and .network == $network and .sourceRanges == [$cidr]
    and (.targetTags // [] | index($tag) != null)
    and (.denied // [] | length == 0)
    and (.allowed | length == 1)
    and (.allowed[0].IPProtocol == "tcp")
    and (.allowed[0].ports == [$port])
  ' "$tmp/rule-$port.json"
done

# Effective policies are more important than the two intended allow rules.
# Fail closed for broad admin allows or unfamiliar hierarchical policies.
# Keep the raw JSON private: it can describe other project resources.
if gcloud compute instances network-interfaces get-effective-firewalls "$instance" --project="$project" --zone="$zone" --format=json >"$tmp/effective.json" 2>"$tmp/effective.err"; then
  label="effective VPC rules have no public/global admin ingress"
  check jq -e --arg cidr "$iap_cidr" '
    def port_covers($wanted):
      (split("-") | map(tonumber)) as $v |
      if ($v | length) == 1 then $v[0] == $wanted
      else $v[0] <= $wanted and $v[1] >= $wanted end;
    def allows_admin:
      any(.allowed[]?;
        (.IPProtocol == "all") or
        (.IPProtocol == "tcp" and
          ((.ports // []) as $ports |
            ($ports | length) == 0 or
            any($ports[]; port_covers(22) or port_covers(3389))
          )
        )
      );
    type == "object"
    and ((.firewalls // []) | all(.[];
      (.disabled == true) or (.direction != "INGRESS") or (allows_admin | not)
      or (
        (.sourceRanges // []) == [$cidr]
        and ((.sourceTags // []) | length == 0)
        and ((.sourceServiceAccounts // []) | length == 0)
      )
    ))
    and ((.firewallPolicys // []) | length == 0)
  ' "$tmp/effective.json"
  # Unknown hierarchical/global rules require explicit operator review;
  # they MUST NOT silently satisfy the audit.
else
  echo "FAIL: effective VPC firewall cannot be inspected" >&2
  status=1
fi

if gcloud services list --enabled --project="$project" --format="value(config.name)" | grep -Fx iap.googleapis.com >/dev/null; then
  number="$(gcloud projects describe "$project" --format='value(projectNumber)')"
  # Avoid echoing tokens or policies. This endpoint reads INSTANCE-scoped IAM.
  if command -v curl >/dev/null && [[ "$number" =~ ^[0-9]+$ ]]; then
    token="$(gcloud auth print-access-token)"
    if curl --fail --silent --show-error --request POST \
      --header "Authorization: Bearer $token" \
      --data '' \
      "https://iap.googleapis.com/v1/projects/$number/iap_tunnel/zones/$zone/instances/$instance:getIamPolicy" \
      >"$tmp/iap-policy.json"; then
      unset token
      label="instance-scoped, port-3389 IAP tunnel IAM binding"
      check jq -e 'any(.bindings[]?;
        .role == "roles/iap.tunnelResourceAccessor"
        and ((.condition.expression // "" | gsub("[[:space:]]"; "")) == "destination.port==3389")
      )' "$tmp/iap-policy.json"
    else
      unset token
      echo "FAIL: instance-scoped IAP IAM policy unavailable" >&2
      status=1
    fi
  else
    echo "FAIL: curl or project number unavailable for IAP audit" >&2
    status=1
  fi
fi

# Success here still does NOT establish an authenticated RDP tunnel, a
# graphical login, port-22 admin policy or stop/start persistence.
echo "NOTE: real RDP/OS Login E2E is a separate blocking acceptance gate."
exit "$status"
