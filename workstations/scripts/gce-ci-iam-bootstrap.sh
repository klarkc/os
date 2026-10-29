#!/usr/bin/env bash
# One-time IAM bootstrap. Must run under the human's Cloud Shell identity.
# The existing buildgce-auditor remains read-only; never create SA keys.
# New WIF pool admits ONLY this deployment workflow on this branch.
set -euo pipefail
umask 077
command -v jq >/dev/null || { echo "FAIL: jq is required in Cloud Shell" >&2; exit 2; }
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

project=argon-surf-472319-b0
number=1009769829445
pool=github-wsklarkc-deploy
provider=wsklarkc-deploy
workflow_ref='klarkc/os/.github/workflows/build-thin-client.yml@refs/heads/feat/wsklarkc-gce'
condition="assertion.repository_id=='639154288' && assertion.repository_owner_id=='724959' && assertion.ref=='refs/heads/feat/wsklarkc-gce' && assertion.workflow_ref=='$workflow_ref'"
member="principalSet://iam.googleapis.com/projects/$number/locations/global/workloadIdentityPools/$pool/attribute.repository_id/639154288"
deployer="buildgce-deployer@$project.iam.gserviceaccount.com"
tester="buildgce-e2e@$project.iam.gserviceaccount.com"

[[ "$(gcloud config get-value project 2>/dev/null)" == "$project" ]] || {
  echo "FAIL: select project $project first" >&2
  exit 1
}
echo "Configuring isolated GitHub WIF pool for this ONE branch and workflow."
echo "Existing auditor identity remains read-only; its branch gate will move."
# Replace, don't widen, the original auditor's branch restriction. The old
# BuildGCE branch is obsolete but contains live workflow code; it must lose
# OIDC access before the new branch gains it.
audit_condition="assertion.repository_id=='639154288' && assertion.repository_owner_id=='724959' && assertion.ref=='refs/heads/feat/wsklarkc-gce'"
gcloud iam workload-identity-pools providers update-oidc github-actions \
  --project="$project" --location=global \
  --workload-identity-pool=github-buildgce \
  --attribute-condition="$audit_condition" --quiet >/dev/null
actual_audit="$(gcloud iam workload-identity-pools providers describe github-actions \
  --project="$project" --location=global \
  --workload-identity-pool=github-buildgce --format='value(attributeCondition)')"
[[ "$actual_audit" == "$audit_condition" ]] || {
  echo "FAIL: original auditor branch restriction was not migrated" >&2
  exit 1
}
echo "PASS: existing READ-ONLY auditor OIDC moved from old branch to wsklarkc"

# IAM creates are eventually consistent: create returning successfully is
# NOT evidence that an immediate describe can see the resource. Retrying
# the whole bootstrap during this window must not re-create the provider.
wait_visible() {
  local what="$1"
  shift
  local attempt
  for attempt in $(seq 1 18); do
    if "$@" >/dev/null 2>&1; then
      echo "PASS: $what is visible (attempt $attempt)"
      return 0
    fi
    if [ "$attempt" -lt 18 ]; then
      echo "WAIT: $what not yet readable; retrying after 5 seconds ($attempt/18)"
      sleep 5
    fi
  done
  echo "FAIL: $what still unavailable after bounded retries" >&2
  return 1
}

pool_describe=(gcloud iam workload-identity-pools describe "$pool" --project="$project" --location=global)
provider_describe=(gcloud iam workload-identity-pools providers describe "$provider" --project="$project" --location=global --workload-identity-pool="$pool")

if ! "${pool_describe[@]}" >/dev/null 2>&1; then
  # A pre-existing resource may briefly report NOT_FOUND during propagation.
  # Do not discard its state or fail on an "already exists" create race.
  if ! gcloud iam workload-identity-pools create "$pool" \
    --project="$project" --location=global \
    --display-name="BuildGCE deploy and E2E workflow"; then
    echo "NOTICE: pool create did not complete; checking for an existing resource" >&2
  fi
fi
wait_visible "WIF pool $pool" "${pool_describe[@]}"
pool_state="$("${pool_describe[@]}" --format='value(state)')"
[[ "$pool_state" == ACTIVE ]] || {
  echo "FAIL: deployment WIF pool must be ACTIVE, found: $pool_state" >&2
  exit 1
}

if ! "${provider_describe[@]}" >/dev/null 2>&1; then
  if ! gcloud iam workload-identity-pools providers create-oidc "$provider" \
    --project="$project" --location=global --workload-identity-pool="$pool" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository_id=assertion.repository_id,attribute.workflow_ref=assertion.workflow_ref" \
    --attribute-condition="$condition"; then
    echo "NOTICE: provider create did not complete; checking for an existing resource" >&2
  fi
fi
wait_visible "WIF provider $provider" "${provider_describe[@]}"

# Reject a provider with a different trust boundary; do not rewrite it
# automatically or silently broaden an existing OIDC mapping/condition.
provider_tmp="$(mktemp)"
trap 'rm -f -- "$provider_tmp"' EXIT
"${provider_describe[@]}" --format=json > "$provider_tmp"
jq -e --arg expected "$condition" '
  .state == "ACTIVE"
  and .attributeCondition == $expected
  and .oidc.issuerUri == "https://token.actions.githubusercontent.com"
  and .attributeMapping["google.subject"] == "assertion.sub"
  and .attributeMapping["attribute.repository_id"] == "assertion.repository_id"
  and .attributeMapping["attribute.workflow_ref"] == "assertion.workflow_ref"
' "$provider_tmp" >/dev/null || {
  echo "FAIL: provider state, issuer, mapping or branch/workflow condition differs" >&2
  exit 1
}
echo "PASS: deployment provider ACTIVE with exact GitHub trust boundary"

for spec in "buildgce-deployer:Approved BuildGCE deployment" "buildgce-e2e:BuildGCE E2E test only"; do
  id="${spec%%:*}"
  display="${spec#*:}"
  sa="$id@$project.iam.gserviceaccount.com"
  if ! gcloud iam service-accounts describe "$sa" --project="$project" >/dev/null 2>&1; then
    if ! gcloud iam service-accounts create "$id" --project="$project" --display-name="$display"; then
      echo "NOTICE: service account create returned an error; checking whether it already exists" >&2
    fi
  fi
  wait_visible "service account $id" gcloud iam service-accounts describe "$sa" --project="$project"
  gcloud iam service-accounts add-iam-policy-binding "$sa" --project="$project" \
    --role=roles/iam.workloadIdentityUser --member="$member" --condition=None --quiet >/dev/null
  echo "PASS: repo-scoped WIF binding for $id"
done

# Limited to the intended project and restricted trusted workflow.
# These roles still have project-wide *resource-management* scope. Review
# and revoke after initial deployment if ongoing admin is not necessary.
for role in roles/compute.instanceAdmin.v1 roles/compute.networkAdmin \
            roles/compute.securityAdmin roles/storage.admin roles/iap.admin; do
  gcloud projects add-iam-policy-binding "$project" \
    --member="serviceAccount:$deployer" --role="$role" --condition=None --quiet >/dev/null
  echo "PASS: deployer role $role"
done

# E2E identity cannot create/stop/delete VMs or alter VPC/IAM.
# After instance creation the DEPLOYMENT job grants osAdminLogin on ONLY
# wsklarkc and instance-specific IAP access for TCP 22 and 3389.
for role in roles/compute.viewer; do
  gcloud projects add-iam-policy-binding "$project" \
    --member="serviceAccount:$tester" --role="$role" --condition=None --quiet >/dev/null
  echo "PASS: E2E viewer role $role"
done

echo "PASS: dedicated WIF deployer + tester ready, no static credential keys"
echo "PENDING: GitHub workflow must prove real service-account impersonation"
echo "PENDING: VM-scoped IAP and OS Login will be configured only after VM exists"
echo "Do not rerun or widen the previous buildgce-auditor identity."
