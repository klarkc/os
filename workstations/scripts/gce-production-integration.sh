#!/usr/bin/env bash
# Fail-closed production checks. This is NOT a substitute for authenticated
# XRDP session testing. Executes with existing read-only WIF auditor identity.
set -euo pipefail
umask 077
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

project=argon-surf-472319-b0
zone=southamerica-east1-b
vm=wsklarkc
network=wsklarkc-iap-vpc
subnet=wsklarkc-iap-subnet
tag=wsklarkc-iap
iap=35.235.240.0/20
expected_image="wsklarkc-nixos-gce-${GITHUB_SHA:0:12}"

for cmd in gcloud python3 jq; do
  command -v "$cmd" >/dev/null || { echo "FAIL: missing $cmd" >&2; exit 2; }
done
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

gcloud compute instances describe "$vm" --project="$project" --zone="$zone" --format=json >"$tmp/vm.json"
boot_uri="$(jq -r '[.disks[]? | select(.boot == true)][0].source // empty' "$tmp/vm.json")"
[[ "$boot_uri" == */disks/* ]] || { echo "FAIL: no boot disk" >&2; exit 1; }
disk="${boot_uri##*/}"
gcloud compute disks describe "$disk" --project="$project" --zone="$zone" --format=json >"$tmp/disk.json"
gcloud compute firewall-rules list --project="$project" --format=json >"$tmp/firewalls.json"
gcloud compute instances network-interfaces get-effective-firewalls "$vm" \
  --project="$project" --zone="$zone" --format=json >"$tmp/effective.json"
gcloud compute images describe "$expected_image" --project="$project" --format=json >"$tmp/image.json"

python3 - "$tmp" "$expected_image" <<'PY'
import ipaddress
import json
import pathlib
import sys

base = pathlib.Path(sys.argv[1])
expected_image = sys.argv[2]
load = lambda name: json.loads((base / (name + ".json")).read_text())
vm, disk, rules, effective, image = map(load, ["vm", "disk", "firewalls", "effective", "image"])
iap = ipaddress.ip_network("35.235.240.0/20")
project = "argon-surf-472319-b0"
network = "wsklarkc-iap-vpc"
tag = "wsklarkc-iap"


def require(ok, label):
    if not ok:
        raise SystemExit("FAIL: " + label)
    print("PASS: " + label)


def suffix(value, name):
    return isinstance(value, str) and value.endswith("/" + name)


require(vm.get("name") == "wsklarkc" and vm.get("status") == "RUNNING",
        "production VM RUNNING")
require(suffix(vm.get("machineType"), "e2-highmem-4"),
        "4-vCPU/32-GiB e2-highmem-4")
require(not vm.get("guestAccelerators"), "no GPU accelerators")
require(len([d for d in vm.get("disks", []) if d.get("boot")]) == 1,
        "exactly one boot disk")
require(all(d.get("autoDelete") is False for d in vm["disks"] if d.get("boot")),
        "boot disk autoDelete=false (survives VM deletion)")
require(str(disk.get("sizeGb")) == "512" and suffix(disk.get("type"), "pd-balanced"),
        "512 GiB pd-balanced persistent disk")
require(disk.get("status") == "READY", "disk ready")
require(image.get("name") == expected_image and image.get("status") == "READY",
        "approved NixOS custom image READY")
source_image = str(disk.get("sourceImage") or "")
require(suffix(source_image, expected_image),
        "boot disk actually created from the approved image")
require(not vm.get("serviceAccounts"), "no attached VM service account")
metadata = {x["key"]: x.get("value", "") for x in vm.get("metadata", {}).get("items", [])}
require(metadata.get("enable-oslogin", "").upper() == "TRUE", "OS Login metadata enabled")
require(tag in vm.get("tags", {}).get("items", []), "isolated IAP network tag")

interfaces = vm.get("networkInterfaces", [])
require(len(interfaces) == 1, "exactly one network interface")
nic = interfaces[0]
require(suffix(nic.get("network"), network), "custom isolated VPC")
require(suffix(nic.get("subnetwork"), "wsklarkc-iap-subnet"), "isolated regional subnet")
require(not nic.get("accessConfigs") and not nic.get("ipv6AccessConfigs"),
        "NO externally accessible VM IP address")

network_url = nic["network"]
on_network = [r for r in rules if r.get("network") == network_url
              and r.get("direction", "INGRESS") == "INGRESS"
              and not r.get("disabled", False)]
require(len(on_network) == 2,
        "only two active classic ingress allow rules on dedicated VPC")
for port, name in [(22, "ssh"), (3389, "rdp")]:
    rule = next((r for r in on_network if r.get("name") == "wsklarkc-iap-" + name), None)
    require(rule is not None and rule.get("sourceRanges") == [str(iap)]
            and rule.get("targetTags") == [tag]
            and not rule.get("sourceTags") and not rule.get("sourceServiceAccounts")
            and rule.get("allowed") == [{"IPProtocol": "tcp", "ports": [str(port)]}]
            and not rule.get("denied"),
            f"VPC tcp/{port} ingress restricted to the IAP proxy range")

require(isinstance(effective, dict) and "firewalls" in effective,
        "effective firewall inspection response includes classic rules")
# Never accept an unknown policy rule that could override ingress.
for policy in effective.get("firewallPolicys", []):
    for r in policy.get("rules", []):
        if r.get("disabled", False) or r.get("action", "").lower() != "allow":
            continue
        # Conservative: a broad inherited allow can defeat dedicated VPC
        # rules, irrespective of NixOS nftables.
        raise SystemExit("FAIL: inherited effective firewall allow requires review")

actual_names = {r.get("name") for r in effective["firewalls"]}
require({"wsklarkc-iap-ssh", "wsklarkc-iap-rdp"} <= actual_names,
        "both IAP-only rules actually apply to this instance")
for r in effective["firewalls"]:
    if r.get("direction", "INGRESS") != "INGRESS" or r.get("disabled", False):
        continue
    for allow in r.get("allowed", []):
        proto = allow.get("IPProtocol", "").lower()
        if proto not in ("tcp", "all"):
            continue
        # Any extra ingress (including port 443/80) is unexpected for the
        # single-purpose XRDP workstation and must be reviewed.
        require(r.get("name") in {"wsklarkc-iap-ssh", "wsklarkc-iap-rdp"}
            and r.get("sourceRanges") == [str(iap)],
            "no unauthorized effective TCP ingress")
print("NOTE: guest nftables, XRDP PAM and XMonad checked only in subsequent authenticated E2E")
PY
echo "PASS: production integration preconditions satisfied"
