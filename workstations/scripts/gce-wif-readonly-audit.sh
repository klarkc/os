#!/usr/bin/env bash
# Read-only GitHub Actions WIF proof and GCP inventory. Do not log tokens,
# credentials, raw IAM policies, project topology or the Cloud SDK environment.
set -euo pipefail
umask 077
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

project=argon-surf-472319-b0
zone=southamerica-east1-b
instance=wsklarkc
service_account="buildgce-auditor@$project.iam.gserviceaccount.com"
principal="principalSet://iam.googleapis.com/projects/1009769829445/locations/global/workloadIdentityPools/github-buildgce/attribute.repository_id/639154288"

for cmd in gcloud jq python3; do
  command -v "$cmd" >/dev/null || { echo "FAIL: missing required $cmd" >&2; exit 2; }
done

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

# This prints a bearer token; discard output, never use shell tracing.
if ! gcloud auth print-access-token > /dev/null; then
  echo "FAIL: GitHub OIDC could not impersonate BuildGCE auditor" >&2
  exit 1
fi
echo "PASS: short-lived Google WIF token exchange succeeded"

# An inherited Owner binding or excess privileges would not be visible from
# this audit alone; no privileged action is attempted or assumed.
gcloud projects get-iam-policy "$project" --format=json > "$tmp/project-iam.json"
for role in roles/compute.viewer roles/iam.securityReviewer roles/serviceusage.serviceUsageViewer; do
  if jq -e --arg role "$role" --arg sa "serviceAccount:$service_account" '
    any(.bindings[]?; .role == $role and ((.members // []) | index($sa) != null))
  ' "$tmp/project-iam.json" > /dev/null; then
    echo "PASS: auditor project role $role"
  else
    echo "FAIL: auditor project role missing: $role" >&2
    exit 1
  fi
done

gcloud iam service-accounts get-iam-policy "$service_account" \
  --project="$project" --format=json > "$tmp/sa-iam.json"
if jq -e --arg member "$principal" '
  any(.bindings[]?; .role == "roles/iam.workloadIdentityUser"
    and ((.members // []) | index($member) != null))
' "$tmp/sa-iam.json" > /dev/null; then
  echo "PASS: repository-scoped WIF service-account trust binding"
else
  echo "FAIL: expected WIF trust binding is missing" >&2
  exit 1
fi

gcloud services list --enabled --project="$project" \
  --format="value(config.name)" > "$tmp/services.txt"
for service in compute.googleapis.com iap.googleapis.com iamcredentials.googleapis.com sts.googleapis.com; do
  if grep -Fx "$service" "$tmp/services.txt" > /dev/null; then
    echo "PASS: API enabled $service"
  else
    # IAP can be intentionally pending before real VM provisioning.
    echo "PENDING: API not enabled: $service"
  fi
done

gcloud compute instances list --project="$project" --format=json > "$tmp/instances.json"
if jq -e --arg name "$instance" --arg zone "$zone" '
  any(.[]?; .name == $name and ((.zone // "") | endswith("/" + $zone)))
' "$tmp/instances.json" > /dev/null; then
  echo "PRESENT: target VM (requires real IAP, XRDP and disk checks)"
else
  echo "PENDING: target VM does not exist in selected zone"
fi

gcloud compute disks list --project="$project" --format=json > "$tmp/disks.json"
echo "INFO: Compute Engine disk count $(jq 'length' "$tmp/disks.json") (no changes made)"

gcloud compute images list --no-standard-images \
  --project="$project" --format=json > "$tmp/images.json"
echo "INFO: custom image count $(jq 'length' "$tmp/images.json") (no import performed)"

# Firewall policy is scoped by network/tags/instance. In the absence of
# a deployed instance, we cannot claim these VPC rules are effective on it.
gcloud compute firewall-rules list --project="$project" \
  --format=json > "$tmp/firewalls.json"
python3 - "$tmp/firewalls.json" <<'PY'
import ipaddress
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fp:
    rules = json.load(fp)

iap = ipaddress.ip_network("35.235.240.0/20")
admin_ports = (22, 3389)


def covers_admin(rule):
    for allow in rule.get("allowed", []):
        proto = str(allow.get("IPProtocol", "")).lower()
        if proto == "all":
            return True
        if proto != "tcp":
            continue
        ports = allow.get("ports", [])
        if not ports:
            return True
        for value in ports:
            parts = str(value).split("-", 1)
            try:
                low = int(parts[0])
                high = int(parts[1]) if len(parts) == 2 else low
            except ValueError:
                continue
            if any(low <= p <= high for p in admin_ports):
                return True
    return False


def allows_outside_iap(rule):
    if rule.get("sourceTags") or rule.get("sourceServiceAccounts"):
        return False
    for value in rule.get("sourceRanges") or ["0.0.0.0/0"]:
        try:
            net = ipaddress.ip_network(value, strict=False)
        except ValueError:
            return True
        if not (net.version == 4 and net.subnet_of(iap)):
            return True
    return False


suspect = [
    r for r in rules
    if r.get("direction", "INGRESS") == "INGRESS"
    and not r.get("disabled", False)
    and covers_admin(r) and allows_outside_iap(r)
]
if suspect:
    print(
        "REVIEW: %d existing VPC allow rules potentially permit admin "
        "ingress from outside IAP; check effective rules on target VM" % len(suspect)
    )
else:
    print("PASS: no broad TCP 22/3389 allow rules detected in classic VPC firewall")
print("NOTE: hierarchical/network policies and effective VM firewall are NOT proven here")
PY

echo "NOTE: WIF audit success does NOT prove IAP tunnel, XRDP GUI login or GCE stop/start"
echo "NOTE: no cloud resources or IAM/VPC policies were created or modified"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### BuildGCE federated GCP audit"
    echo "WIF authentication and read-only role checks: **passed**."
    echo "VM and end-to-end IAP/XRDP/stop-start: **pending separate acceptance**."
    echo "No resources created; no credentials committed or printed."
  } >> "$GITHUB_STEP_SUMMARY"
fi
