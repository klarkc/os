#!/usr/bin/env bash
# One-time Cloud Shell deployment of the APPROVED, tested NixOS GCE image.
# Requires operator's authenticated gcloud and gh. No credentials in git,
# image, instance metadata or logging; no IAM role escalation.
# Flags: --preflight (read-only) and --deploy (creates authorized resources).
set -euo pipefail
umask 077
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

project=argon-surf-472319-b0
project_number=1009769829445
zone=southamerica-east1-b
region=southamerica-east1
vm=solo-workstation
network=solo-iap-vpc
subnet=solo-iap-subnet
subnet_cidr=10.83.0.0/24
tag=solo-workstation-iap
sha=96a98ff35863d96ad21d42180f8f10650422c5d2
run_id=40521793755
artifact="solo-gce-image-$sha"
image="solo-nixos-gce-${sha:0:12}"
bucket="solo-gce-image-$project_number"
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
echo "APPROVED PLAN: $vm ($zone), e2-highmem-4, 512 GiB pd-balanced boot disk"
echo "NETWORK: dedicated $network + $subnet; ingress TCP 22/3389 only from 35.235.240.0/20"
echo "EGRESS: ephemeral public IPv4 (no static IP, no Cloud NAT); no other allowed ingress"
echo "IMAGE: successful GitHub Actions run $run_id, commit $sha"
echo "STAGING: temporary private Cloud Storage bucket for tar.gz image import"
if [[ "$1" == --preflight ]]; then
  echo "READ-ONLY: no resources created"
  exit 0
fi

[[ "${SOLO_GCE_DEPLOY_APPROVED:-}" == YES ]] || {
  echo "FAIL: require SOLO_GCE_DEPLOY_APPROVED=YES for actual deployment" >&2
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
     (.targetTags == ["solo-workstation-iap"]))))
' "$tmp/vpc.json" >/dev/null || { echo "FAIL: unexpected network ingress rules" >&2; exit 1; }

# Image is built already; no Nix recompilation on Cloud Shell.
gcloud storage buckets create "gs://$bucket" --project="$project" \
  --location="$region" --default-storage-class=STANDARD \
  --uniform-bucket-level-access --public-access-prevention
gcloud storage cp --no-user-output-enabled "$archive" "$uri"
gcloud compute images create "$image" --project="$project" \
  --source-uri="$uri" --storage-location="$region" \
  --guest-os-features=VIRTIO_SCSI_MULTIQUEUE
echo "PASS: custom NixOS image imported"

# Remove the staging object and bucket only after image import succeeds.
gcloud storage rm "$uri"
gcloud storage buckets delete "gs://$bucket" --quiet

# Explicit parameters make it impossible to accidentally provision Debian,
# a smaller auto-deleted disk, a machine with a GPU or the default VPC.
# The VM receives no GCE service account or OAuth API scopes.
gcloud compute instances create "$vm" --project="$project" --zone="$zone" \
  --machine-type=e2-highmem-4 --image="$image" --image-project="$project" \
  --boot-disk-size=512GB --boot-disk-type=pd-balanced \
  --no-boot-disk-auto-delete --no-service-account --no-scopes \
  --network-interface="network=$network,subnet=$subnet,stack-type=IPV4_ONLY" \
  --tags="$tag" --metadata=enable-oslogin=TRUE \
  --shielded-vtpm --shielded-integrity-monitoring \
  --labels=managed-by=buildgce,environment=development

echo "INSTANCE CREATED: run the fail-closed VPC and IAP authorization audit next."
echo "IMPORTANT: the IAP principal role, interactive XRDP password and graphical login are not configured by this script."
echo "IMPORTANT: stop the VM after testing to limit compute cost; disk/image still incur storage cost."
