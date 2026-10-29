#!/usr/bin/env bash
# GitHub Actions deploy coordinator. Runs only after approved image CI,
# WIF attestation and IAM bootstrap. Idempotent on a matching existing VM.
# Never silently replace or delete a preexisting resource.
set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
project=argon-surf-472319-b0
zone=southamerica-east1-b
vm=wsklarkc

for cmd in gcloud gh jq; do command -v "$cmd" >/dev/null || { echo "FAIL: missing $cmd" >&2; exit 2; }; done
[[ "${WSKLARKC_GCE_DEPLOY_APPROVED:-}" == YES ]] || { echo "FAIL: cost approval gate is not set" >&2; exit 2; }
[[ "${GITHUB_REPOSITORY:-}" == klarkc/os ]] || { echo "FAIL: untrusted repository" >&2; exit 2; }
[[ "${GITHUB_REF:-}" == refs/heads/feat/wsklarkc-gce ]] || { echo "FAIL: untrusted branch" >&2; exit 2; }
[[ "${GITHUB_WORKFLOW:-}" == "NixOS thin client + workstation CI" ]] || {
  echo "FAIL: must execute via the approved deployment workflow" >&2; exit 2;
}

if gcloud compute instances describe "$vm" --project="$project" --zone="$zone" --format=json >/dev/null 2>&1; then
  echo "EXISTING: $vm; refusing to create another VM or replace boot disk"
  # The next job ALWAYS validates every instance property, disk, network
  # and effective firewall before authorizing E2E; no automatic drift fix.
else
  echo "CREATING: exactly one approved NixOS VM; disk 256 GiB, no public IP"
  WSKLARKC_GCE_DEPLOY_APPROVED=YES bash workstations/scripts/gce-provision-approved.sh --deploy
fi
gcloud compute instances describe "$vm" --project="$project" --zone="$zone" \
  --format='value(status)' | grep -Fx RUNNING >/dev/null || {
    echo "FAIL: approved VM is not running" >&2
    exit 1
  }
echo "PASS: VM is RUNNING; next job MUST validate production shape and firewall"
