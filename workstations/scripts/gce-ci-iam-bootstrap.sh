#!/usr/bin/env bash
# One-time IAM bootstrap. Must run under the human's Cloud Shell identity.
# The existing buildgce-auditor remains read-only; never create SA keys.
# New WIF pool admits ONLY this deployment workflow on this branch.
set -euo pipefail
umask 077
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

project=argon-surf-472319-b0
number=1009769829445
pool=github-buildgce-prod
provider=buildgce-deploy-e2e
workflow_ref='klarkc/os/.github/workflows/gce-deploy-e2e.yml@refs/heads/feat/solo-gce-workstation-20261026'
condition="assertion.repository_id=='639154288' && assertion.repository_owner_id=='724959' && assertion.ref=='refs/heads/feat/solo-gce-workstation-20261026' && assertion.workflow_ref=='$workflow_ref'"
member="principalSet://iam.googleapis.com/projects/$number/locations/global/workloadIdentityPools/$pool/attribute.repository_id/639154288"
deployer="buildgce-deployer@$project.iam.gserviceaccount.com"
tester="buildgce-e2e@$project.iam.gserviceaccount.com"

[[ "$(gcloud config get-value project 2>/dev/null)" == "$project" ]] || {
  echo "FAIL: select project $project first" >&2
  exit 1
}
echo "Configuring isolated GitHub WIF pool for this ONE branch and workflow."
echo "Existing auditor identity will remain unchanged."

if ! gcloud iam workload-identity-pools describe "$pool" --project="$project" --location=global >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "$pool" --project="$project" --location=global \
    --display-name="BuildGCE deploy and E2E workflow"
fi
if ! gcloud iam workload-identity-pools providers describe "$provider" \
    --project="$project" --location=global --workload-identity-pool="$pool" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools providers create-oidc "$provider" \
    --project="$project" --location=global --workload-identity-pool="$pool" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository_id=assertion.repository_id,attribute.workflow_ref=assertion.workflow_ref" \
    --attribute-condition="$condition"
fi

actual="$(gcloud iam workload-identity-pools providers describe "$provider" \
  --project="$project" --location=global --workload-identity-pool="$pool" \
  --format='value(attributeCondition)')"
[[ "$actual" == "$condition" ]] || { echo "FAIL: WIF provider has unexpected security conditions" >&2; exit 1; }
state="$(gcloud iam workload-identity-pools providers describe "$provider" \
  --project="$project" --location=global --workload-identity-pool="$pool" \
  --format='value(state)')"
[[ "$state" == ACTIVE ]] || { echo "FAIL: WIF provider is not ACTIVE" >&2; exit 1; }

for spec in "buildgce-deployer:Approved BuildGCE deployment" "buildgce-e2e:BuildGCE E2E test only"; do
  id="${spec%%:*}"
  display="${spec#*:}"
  sa="$id@$project.iam.gserviceaccount.com"
  if ! gcloud iam service-accounts describe "$sa" --project="$project" >/dev/null 2>&1; then
    gcloud iam service-accounts create "$id" --project="$project" --display-name="$display"
  fi
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
# solo-workstation and instance-specific IAP access for TCP 22 and 3389.
for role in roles/compute.viewer; do
  gcloud projects add-iam-policy-binding "$project" \
    --member="serviceAccount:$tester" --role="$role" --condition=None --quiet >/dev/null
  echo "PASS: E2E viewer role $role"
done

echo "PASS: dedicated WIF deployer + tester ready, no static credential keys"
echo "PENDING: GitHub workflow must prove real service-account impersonation"
echo "PENDING: VM-scoped IAP and OS Login will be configured only after VM exists"
echo "Do not rerun or widen the previous buildgce-auditor identity."
