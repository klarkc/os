#!/usr/bin/env bash
# Post-firewall-review authorization: grant CI E2E account only on
# solo-workstation; never change the human Dell principal or project Owner.
set -euo pipefail
umask 077
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

project=argon-surf-472319-b0
number=1009769829445
zone=southamerica-east1-b
vm=solo-workstation
tester="buildgce-e2e@$project.iam.gserviceaccount.com"

# OS Login with sudo is needed only to create/delete a disposable RDP user
# and verify guest services. It is scoped to ONE VM, not all project VMs.
gcloud compute instances add-iam-policy-binding "$vm" --project="$project" --zone="$zone" \
  --member="serviceAccount:$tester" --role=roles/compute.osAdminLogin \
  --condition=None --quiet >/dev/null
echo "PASS: E2E account has instance-scoped OS Admin Login"

# The gcloud CLI lacks the same consistent IAM helper across all IAP TCP
# instance resources. Use documented IAP v1 get/set IAM REST APIs;
# preserve etag/other users' bindings, never print access token or policies.
python3 - "$number" "$zone" "$vm" "$tester" <<'PY'
import json
import subprocess
import sys
import urllib.request

number, zone, instance, tester = sys.argv[1:]
token = subprocess.check_output(
    ["gcloud", "auth", "print-access-token"], text=True
).strip()
base = (
    f"https://iap.googleapis.com/v1/projects/{number}/iap_tunnel/"
    f"zones/{zone}/instances/{instance}"
)
member = "serviceAccount:" + tester
role = "roles/iap.tunnelResourceAccessor"
condition = {
    "title": "buildgce-e2e-only-ssh-and-rdp",
    "description": "CI service account: only TCP 22/3389 on solo-workstation",
    "expression": "destination.port == 22 || destination.port == 3389",
}


def request(method, endpoint, payload):
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        base + ":" + endpoint,
        data=body,
        method=method,
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer " + token,
        },
    )
    with urllib.request.urlopen(req, timeout=40) as response:
        return json.load(response)


policy = request("POST", "getIamPolicy", {"options": {"requestedPolicyVersion": 3}})
bindings = policy.setdefault("bindings", [])
matched = False
for binding in bindings:
    if binding.get("role") != role or member not in binding.get("members", []):
        continue
    if binding.get("condition", {}).get("expression") != condition["expression"]:
        raise SystemExit("FAIL: tester has a preexisting overbroad IAP IAM binding")
    matched = True

if not matched:
    bindings.append({"role": role, "members": [member], "condition": condition})
    policy["version"] = 3
    request("POST", "setIamPolicy", {"policy": policy})
    check = request("POST", "getIamPolicy", {"options": {"requestedPolicyVersion": 3}})
    if not any(
        b.get("role") == role and member in b.get("members", [])
        and b.get("condition", {}).get("expression") == condition["expression"]
        for b in check.get("bindings", [])
    ):
        raise SystemExit("FAIL: IAP E2E instance IAM binding was not persisted")
print("PASS: tester IAP instance role restricted to TCP 22/3389")
PY
