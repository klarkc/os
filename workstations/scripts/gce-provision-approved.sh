#!/usr/bin/env bash
# GitHub Actions deployment of the approved, tested NixOS GCE image.
# Uses scoped WIF identity and ephemeral GitHub Actions GH_TOKEN. No credentials in git,
# image, instance metadata or logging; no IAM role escalation.
# Flags: --preflight (read-only) and --deploy (creates authorized resources).
set -euo pipefail
umask 077
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

project=argon-surf-472319-b0
project_number=1009769829445
zone=southamerica-east1-b
region=southamerica-east1
vm=wsklarkc
network=wsklarkc-iap-vpc
subnet=wsklarkc-iap-subnet
subnet_cidr=10.83.0.0/24
tag=wsklarkc-iap
sha="${GITHUB_SHA:-}"
run_id="${GITHUB_RUN_ID:-}"
artifact="wsklarkc-gce-image-$sha"
image="wsklarkc-nixos-gce-${sha:0:12}"
bucket="wsklarkc-gce-image-$project_number"
uri="gs://$bucket/$image.raw.tar.gz"

usage() { echo "Usage: $0 --preflight | --deploy" >&2; exit 2; }
[[ "${1:-}" == --preflight || "${1:-}" == --deploy ]] || usage

for cmd in gcloud jq gh sha256sum tar; do
  command -v "$cmd" >/dev/null || { echo "FAIL: missing $cmd" >&2; exit 2; }
done

active_project="$(gcloud config get-value project 2>/dev/null)"
[[ "$active_project" == "$project" ]] || { echo "FAIL: Cloud Shell project mismatch" >&2; exit 1; }

# Verify cloud resources before any write (do NOT print IAM, user identity, tokens).
gcloud compute machine-types describe e2-highmem-4 --project="$project" --zone="$zone" --format='value(name)' | grep -Fx e2-highmem-4 >/dev/null
if gcloud compute instances describe "$vm" --project="$project" --zone="$zone" --format='value(name)' >/dev/null 2>&1; then
  echo "FAIL: VM already exists: refusing to overwrite or attach a new disk" >&2
  exit 1
fi
if gcloud compute images describe "$image" --project="$project" --format='value(name)' >/dev/null 2>&1; then
  echo "FAIL: custom image already exists: inspect manually before continuing" >&2
  exit 1
fi
if gcloud compute networks describe "$network" --project="$project" --format='value(name)' >/dev/null 2>&1; then
  echo "FAIL: dedicated VPC already exists: refuse potentially incompatible firewall configuration" >&2
  exit 1
fi
if gcloud storage buckets describe "gs://$bucket" --format='value(name)' >/dev/null 2>&1; then
  echo "FAIL: staging bucket already exists: refuse to reuse or delete unknown objects" >&2
  exit 1
fi

echo "PRECHECK PASS: target resources absent; machine type available"
echo "APPROVED PLAN: $vm ($zone), e2-highmem-4, 256 GiB pd-balanced boot disk"
echo "NETWORK: dedicated $network + $subnet; ingress TCP 22/3389 only from 35.235.240.0/20"
echo "EGRESS: initially NO external IP; add ephemeral IPv4 only after effective firewall audit"
echo "IMAGE: successful GitHub Actions run $run_id, commit $sha"
echo "STAGING: temporary private Cloud Storage bucket for tar.gz image import"
if [[ "$1" == --preflight ]]; then
  echo "READ-ONLY: no resources created"
  exit 0
fi

[[ "$sha" =~ ^[a-f0-9]{40}$ && "$run_id" =~ ^[0-9]+$ ]] || {
  echo "FAIL: missing verified CI run provenance (GITHUB_SHA/RUN_ID)" >&2
  exit 2
}
[[ "${GITHUB_REF:-}" == refs/heads/feat/wsklarkc-gce ]] || {
  echo "FAIL: untrusted deployment branch" >&2
  exit 2
}
[[ "${WSKLARKC_GCE_DEPLOY_APPROVED:-}" == YES ]] || {
  echo "FAIL: require WSKLARKC_GCE_DEPLOY_APPROVED=YES for actual deployment" >&2
  exit 2
}

# gh must already be authenticated; don't request tokens on stdout.
gh auth status >/dev/null 2>&1 || { echo "FAIL: gh CLI needs authorization to download the GitHub Actions artifact" >&2; exit 2; }
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
gh run download "$run_id" -R klarkc/os -n "$artifact" -D "$tmp"
mapfile -t archives < <(find "$tmp" -maxdepth 1 -type f -name '*.raw.tar.gz')
[[ ${#archives[@]} -eq 1 ]] || { echo "FAIL: expected exactly one NixOS raw image archive" >&2; exit 1; }
archive="${archives[0]}"
(cd "$tmp" && sha256sum -c SHA256SUMS)
tar -tzf "$archive" | grep -Fx disk.raw >/dev/null
echo "PASS: exact CI artifact archive + checksum verified"

# Create isolated network with NO default-allow-ssh/rpc/rdp rule.
gcloud compute networks create "$network" --project="$project" --subnet-mode=custom
gcloud compute networks subnets create "$subnet" --project="$project" \
  --network="$network" --region="$region" --range="$subnet_cidr" --enable-private-ip-google-access

for port in 22 3389; do
  if [[ "$port" == 22 ]]; then suffix=ssh; else suffix=rdp; fi
  gcloud compute firewall-rules create "$vm-iap-$suffix" --project="$project" \
    --network="$network" --direction=INGRESS --priority=1000 \
    --source-ranges=35.235.240.0/20 --target-tags="$tag" \
    --allow="tcp:$port"
done

# Fail before import/VM if an unexpected global/hierarchical or classic rule
# targets this new network. Network policies require separate operator audit.
gcloud compute firewall-rules list --project="$project" \
  --filter="network:$network" --format=json >"$tmp/vpc.json"
jq -e --arg vm "$vm" '
  ([.[] | select(.disabled != true and .direction == "INGRESS")] | length) == 2
  and (all(.[]; .disabled == true or .direction != "INGRESS" or
    (.sourceRanges == ["35.235.240.0/20"] and
     (.targetTags == ["wsklarkc-iap"]))))
' "$tmp/vpc.json" >/dev/null || { echo "FAIL: unexpected network ingress rules" >&2; exit 1; }

# Image is built already; no Nix recompilation on Cloud Shell.
gcloud storage buckets create "gs://$bucket" --project="$project" \
  --location="$region" --default-storage-class=STANDARD \
  --soft-delete-duration=0 \
  --uniform-bucket-level-access --public-access-prevention
gcloud storage cp --quiet "$archive" "$uri"
gcloud compute images create "$image" --project="$project" \
  --source-uri="$uri" --storage-location="$region" \
  --guest-os-features=VIRTIO_SCSI_MULTIQUEUE
echo "PASS: custom NixOS image imported"

# Remove the staging object and bucket only after image import succeeds.
gcloud storage rm "$uri"
gcloud storage buckets delete "gs://$bucket" --quiet

# The pinned NixOS Google image currently uses an MBR/legacy boot layout.
# Google Shielded VM requires a UEFI/GPT custom image, so DO NOT force vTPM
# or integrity monitoring on this image. Migrate image boot layout separately
# and test its boot/recovery before enabling Shielded VM.
# Explicit parameters make it impossible to accidentally provision Debian,
# a smaller auto-deleted disk, a machine with a GPU or the default VPC.
# The VM receives no GCE service account or OAuth API scopes.
gcloud compute instances create "$vm" --project="$project" --zone="$zone" \
  --machine-type=e2-highmem-4 --image="$image" --image-project="$project" \
  --boot-disk-size=256GB --boot-disk-type=pd-balanced \
  --no-boot-disk-auto-delete --no-service-account --no-scopes \
  --network-interface="network=$network,subnet=$subnet,stack-type=IPV4_ONLY,no-address" \
  --tags="$tag" --metadata=enable-oslogin=TRUE \
  --labels=managed-by=buildgce,environment=development

echo "INSTANCE CREATED WITHOUT PUBLIC IP: verify effective VPC and hierarchical firewall policies before adding egress."
echo "IMPORTANT: the IAP principal role, interactive XRDP password and graphical login are not configured by this script."
 echo "After successful effective-firewall audit, enable low-cost outbound access with:"
 echo "gcloud compute instances add-access-config $vm --project=$project --zone=$zone --network-interface=nic0"
 echo "That assigns an EPHEMERAL public IP; never expose ports 22/3389 outside IAP."
echo "COST: 256 GiB pd-balanced/4vCPU/32GiB at 172 active hours ~R$557.50 per month (2026-10-29 catalog), EXCLUDING ancillary services. R$560 is not a hard cap or a deploy authorization."
echo "LIFECYCLE v2: DO NOT stop/start the workstation to reduce costs; it loses RAM and active sessions. Only approved Compute Engine suspend/resume may qualify after independent compatibility E2E."
