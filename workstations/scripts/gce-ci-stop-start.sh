#!/usr/bin/env bash
# Uses deployer WIF identity, NOT E2E login identity.
# Real Compute Engine stop/start must retain the same boot disk and
# instance ID, before a second authenticated XRDP login.
set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
project=argon-surf-472319-b0
zone=southamerica-east1-b
vm=wsklarkc
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

[[ "${GITHUB_REPOSITORY:-}" == klarkc/os &&
   "${GITHUB_REF:-}" == refs/heads/feat/wsklarkc-gce ]] || {
  echo "FAIL: untrusted deployment environment" >&2
  exit 2
}

gcloud compute instances describe "$vm" --project="$project" --zone="$zone" --format=json >"$tmp/before.json"
jq -e '
  .status == "RUNNING" and
  ([.disks[]? | select(.boot == true and .autoDelete == false)] | length == 1)
' "$tmp/before.json" >/dev/null || {
  echo "FAIL: instance not running with persistent boot disk" >&2
  exit 1
}
boot_uri="$(jq -r '[.disks[]? | select(.boot == true)][0].source' "$tmp/before.json")"
instance_id="$(jq -r '.id' "$tmp/before.json")"
test -n "$boot_uri" && test -n "$instance_id"

echo "GATE: stopping the real Compute Engine workstation"
gcloud compute instances stop "$vm" --project="$project" --zone="$zone" --quiet >/dev/null
status="$(gcloud compute instances describe "$vm" --project="$project" --zone="$zone" --format='value(status)')"
[[ "$status" == TERMINATED || "$status" == STOPPED ]] || {
  echo "FAIL: VM did not stop" >&2
  exit 1
}
echo "PASS: Compute Engine stopped the VM"

echo "GATE: starting the SAME VM and persistent disk"
gcloud compute instances start "$vm" --project="$project" --zone="$zone" --quiet >/dev/null
gcloud compute instances describe "$vm" --project="$project" --zone="$zone" --format=json >"$tmp/after.json"
jq -e --arg id "$instance_id" --arg disk "$boot_uri" '
  .status == "RUNNING"
  and .id == $id
  and ([.disks[]? | select(.boot == true and .autoDelete == false and .source == $disk)] | length == 1)
  and ([.networkInterfaces[]?.accessConfigs[]?] | length == 0)
' "$tmp/after.json" >/dev/null || {
  echo "FAIL: stop/start changed instance, boot disk or public-IP policy" >&2
  exit 1
}
echo "PASS: real stop/start retained same instance ID, disk and no public IPv4"
echo "NOTE: HOME marker and authenticated graphical reconnection are tested by the following job"
