# BuildGCE: persistent NixOS workstation via Google Cloud IAP TCP

Canonical contract: https://github.com/klarkc/os/issues/21.
The previous Tailscale/WireGuard integration is obsolete. This server branch
MUST NOT depend on a VPN daemon, external VPN keys, UDP/51820 or metadata
containing peer public keys. The Dell integration is owned by BuildClient.

## Scope and state

- Project: `argon-surf-472319-b0`; zone: `southamerica-east1-b`.
- Planned VM: `solo-workstation`, `e2-highmem-4`, 4 vCPU/32 GiB, no GPU.
- Persistent boot disk candidate: 512 GiB `pd-balanced`, retained on stop.
  The disk is provisioned at 512 GiB even when the VM is stopped; plan for
  full-month block-storage charges and set `autoDelete=false` explicitly.
  The legacy solo098 used a physical 512-GB NVMe with Btrfs subvolumes;
  this is **capacity parity**, not physical NVMe or filesystem parity.
  The standard Google Compute Engine NixOS image filesystem must be checked
  before claiming Btrfs, partition layout or swap equivalence.
- Local account `klarkc`, HOME `/home/klarkc` for direct Git checkout
  `https://github.com/klarkc/dotfiles` (no `/home/klarkc/dotfiles`).
- Display: XRDP on TCP 3389 with **XOrg/XMonad only**. When the
  HOME wrapper exists, XRDP launches it; before restoring dotfiles
  the NixOS XMonad starts directly under D-Bus. **No XFCE**, which
  was unused on solo098, and **no Lemurs**, a local TTY login manager
  that does not handle XRDP authentication. Password initially locked.
- Both OS firewall and GCE VPC firewall restrict admin ports to the IPv4
  Google IAP source `35.235.240.0/20`. SSH 22 is for OS Login admin only,
  not the Dell graphical user workflow.
- This document does not authorize billable GCE operations. **No VM, firewall,
  NAT, public IP, image, disk, bucket or IAM policy is created by CI.**

## CI gates

Run `nix flake check` from `workstations/`, then
`nix build .#checks.x86_64-linux.gce-workstation-security-vm` and
`nix build .#gce-image`.
The GitHub Actions `gce-image` job depends on the dedicated GCE QEMU VM
test. It builds the NixOS `*.raw.tar.gz` custom-image import archive and
uploads SHA256 checksums. Do not import the Dell Ventoy ISO as a server image.

Gates include SSH key-only config, nftables/IAP restrictions, absence of VPN,
XRDP/Xorg/XMonad-only session, no XFCE/Lemurs, no empty XRDP password,
and writable HOME
surviving guest reboot. QEMU checks cannot validate IAM, the real Cloud VPC
firewall, IAP tunnel, Google OS Login, GUI authentication, GCE disk retention
or Dell credentials. Those remain real-world acceptance gates.

## IAM prerequisites (verify in GCP)

Enable `compute.googleapis.com` and `iap.googleapis.com`. Ensure the
authenticated Dell principal can query `compute.instances.get` and
`compute.instances.list` and has `iap.tunnelInstances.accessViaIAP`.
Prefer `roles/iap.tunnelResourceAccessor` directly on the IAP resource for
this VM, with IAM condition `destination.port == 3389` for daily desktop
use. Do not give Instance Admin just to run RDP. For instance discovery,
use a narrowly scoped custom viewer role if feasible.

For one-time administration over port 22, use a distinct IAP binding
condition `destination.port == 22`, Google OS Login with
`roles/compute.osAdminLogin` for the admin principal, and project
`compute.projects.get` for `gcloud compute ssh`. A VM service account may
add `roles/iam.serviceAccountUser` requirements for SSH. Narrow the
permissions and remove the SSH/22 IAP grant after initial setup if no
longer needed. Do not persist credentials or tokens in versioned files.

Check whether the IAP instance IAM policy inherits broader project-level
access, particularly Owner permissions. Instance-scoped condition does
not override a broader inherited binding. Always verify the *effective*
principal authorization for both ports.

Sources:
https://docs.cloud.google.com/iap/docs/using-tcp-forwarding
https://docs.cloud.google.com/compute/docs/oslogin/set-up-oslogin

## VPC firewall: only proxy ingress

First inspect the actual VM network; do not assume it uses `default`.
The `solo-workstation-iap` network tag must be attached only to the
intended workstation. After approval, add two INGRESS allow rules on
that network, targeting only that tag:

```bash
# Set NETWORK to the VM's verified network name.
gcloud compute firewall-rules create solo-workstation-iap-rdp \
  --project=argon-surf-472319-b0 --network="$NETWORK" \
  --direction=INGRESS --priority=900 --action=ALLOW \
  --target-tags=solo-workstation-iap --source-ranges=35.235.240.0/20 \
  --rules=tcp:3389

gcloud compute firewall-rules create solo-workstation-iap-ssh \
  --project=argon-surf-472319-b0 --network="$NETWORK" \
  --direction=INGRESS --priority=900 --action=ALLOW \
  --target-tags=solo-workstation-iap --source-ranges=35.235.240.0/20 \
  --rules=tcp:22
```

Review `default-allow-ssh`, `default-allow-rdp`, global/hierarchical
policies, target tags and effective ingress. A public `0.0.0.0/0`
allow on 22 or 3389 applying to this VM is a **NO-GO** even if the
NixOS firewall also restricts it. Port 51820/UDP must not be opened.

```bash
gcloud compute instances network-interfaces get-effective-firewalls \
  solo-workstation --project=argon-surf-472319-b0 \
  --zone=southamerica-east1-b --format=json
bash workstations/scripts/gce-iap-preflight.sh
```

The read-only preflight checks IAP API, image metadata, VM shape and
explicit firewall/IAM bindings. Independently review effective policy
output; the script does not establish an end-to-end tunnel.

## Network egress: compare before approval

IAP TCP never requires a VM public IP. For outbound access to GitHub, Nix
binary caches and SoloSIG, however, a VM without a public IP needs NAT or
another existing approved egress path.

- **Recommended for intermittent ~172 hours/month:** ephemeral external
  IPv4 on the VM for outbound use only, with *no* public ingress to
  TCP 3389/22, enforced by VPC *and* NixOS nftables. It is released
  when the instance stops. The IP is not used for client connectivity.
- **More isolated but costlier:** no VM external IP + Cloud NAT. Public NAT
  has a per-VM gateway hourly fee, NAT IP hourly charge (including while
  the NAT IP remains allocated), $0.045/GiB processed and normal egress.
  A NAT gateway/IP is not an extra assurance of IAP authentication.

Public IPv4 standard VM usage is published at US$0.005/hour; at 172h
roughly US$0.86/month. For one NAT-assigned VM, the NAT service fee is
US$0.0014/VM-hour plus a NAT IP at US$0.005/hour, plus $0.045/GiB
processed (in addition to egress). If the NAT address remains allocated
730h, the address alone costs about US$3.65. These are illustrative
network components, not a complete invoice. Quote E2 São Paulo,
512GiB pd-balanced for the *full* month, egress, image storage, taxes
and all quotas before approving VM provisioning.

Sources: https://cloud.google.com/vpc/pricing
https://cloud.google.com/nat/pricing
https://cloud.google.com/products/compute/pricing/general-purpose
https://cloud.google.com/compute/disks-image-pricing

## Image and provisioning (approval required)

1. Verify completed CI for the exact commit, SHA256, `disk.raw` inside
   `*.raw.tar.gz`, with no credential material baked into the image.
2. Copy the archive into a private Cloud Storage bucket in an approved
   location. Import with `gcloud compute images create ... --source-uri=gs://...`.
   Do not use Debian/Ubuntu instead of the NixOS custom image.
3. Confirm free quota in `southamerica-east1-b`, disk size and budget
   alerts. Create the VM from that image with boot disk `pd-balanced`
   persistent and `autoDelete=false`; assign the dedicated network tag
   and metadata `enable-oslogin=TRUE`. Never add VPN keys or passwords.
4. Choose ephemeral public egress IPv4 (preferred cost) or an explicitly
   approved preexisting Cloud NAT path. No static IP required.
5. Install the restrictive VPC firewall rules before attempting IAP.
   Never expose public administrative/RDP ports as a workaround.

## Interactive administration and XRDP login

Only after authorized provisioning and IAM + firewall verification:

```bash
gcloud compute ssh solo-workstation \
  --project=argon-surf-472319-b0 \
  --zone=southamerica-east1-b --tunnel-through-iap
# From inside the authenticated admin SSH tty:
sudo solo-xrdp-set-password
```

This delegates to `passwd klarkc` and refuses non-interactive input.
No password, hash or secret passes through shell arguments, metadata,
Git, image store or CI. XRDP login remains locked until this succeeds.
The OS Login account can be different from `klarkc`; verify it explicitly.

Use a separate `klarkc/os` checkout to launch the guarded
`workstations/scripts/bootstrap-dotfiles.sh` as `klarkc`. It creates
the dotfiles Git checkout **directly at HOME**, only if there are no
conflicting tracked paths. The existing `klarkc/dotfiles#default` profile
still includes GPU/Arch-specific pieces; do not silently install them on
the CPU-only workstation. SoloSIG environment/toolchain compatibility
must be verified separately before claiming full parity.

## Real Dell IAP/RDP acceptance, owned jointly with BuildClient

The Dell's gcloud auth is BuildClient's responsibility; no auth state,
tokens or secrets are baked into the ISO, server image or public Git.

```bash
gcloud compute start-iap-tunnel solo-workstation 3389 \
  --project=argon-surf-472319-b0 \
  --zone=southamerica-east1-b \
  --local-host-port=localhost:13389
# Keep the tunnel process running in another terminal.
xfreerdp /v:127.0.0.1:13389 /f /dynamic-resolution /cert:tofu /sec:tls
```

Record: authenticated tunnel establishment, actual remote TCP 3389,
interactive graphical login as `klarkc`, Xorg/XMonad only,
fullscreen/resizing, reconnect after IAP interruption, and post-stop/start
return. The VM must retain `/home/klarkc/.git` and a real writable marker
after a GCE stop/start, not just a QEMU reboot. Verify the boot disk remains
attached and persistent. Do not claim E2E complete from green CI alone.

**BuildClient handoff confirmed (2026-10-27):** the independent client branch
`feat/solo-thin-client-ci-20261026`, commit
`94ea18bf8bdef3bcfe1ff68ef9c363bcc71c72bb`, implements IAP TCP
at `127.0.0.1:13389`, USB persistence for gcloud CLI credentials and
FreeRDP TLS trust pins, and reconnect/error handling. Its GitHub Actions
run https://github.com/klarkc/os/actions/runs/40400809864 passed its
NixOS evaluation, QEMU reboot/persistence, and ISO gates. It did **not**
authenticate against Google or reach this workstation over real IAP.
BuildGCE must not edit the client's branch. The physical Dell Wi-Fi and
authenticated graphical integration remain E2E acceptance gates.

**BuildGCE CI evidence (2026-10-27):** HEAD
`248df1ff088119a51a7c9b7fe3a23bd172ffe346`; run
https://github.com/klarkc/os/actions/runs/40402732649 passed NixOS
evaluation, combined/USB QEMU checks, dedicated IAP server QEMU reboot
test, client ISO build, and GCE raw image build. The CI GCE artifact is
`solo-gce-image-248df1ff088119a51a7c9b7fe3a23bd172ffe346`,
artifact ID `12690415833`. This is a build artifact, **not** an imported
Compute Engine image and not real IAP/RDP validation.

**Live cloud read-only verification (2026-10-27):** Compute Engine
lists **zero VM instances, zero zonal disks, zero custom images, and zero
snapshots** in `argon-surf-472319-b0` (zone
`southamerica-east1-b` for zonal resources). Consequently the intended
instance's IAM bindings, VPC effective rules, IAP tunnel, XRDP login,
persisted HOME and stop/start could not be validated. The connected
Compute Engine integration does not expose the Service Usage, IAM,
IAP or VPC firewall APIs. Their existence or configuration must not be
inferred from a green NixOS CI.

**Provisioning gate:** before importing images or creating VM, disk,
bucket, firewall, IAM policy, NAT or paid IP resources, obtain explicit
cost authorization, check quota and regional prices, audit existing VPC
rules and IAM using an authenticated tool with appropriate permissions,
and prove that the intended VM will not have globally exposed
administrative ports. The standalone `gce-iap-preflight.sh` can audit
these controls **after** the instance exists, from an authenticated
`gcloud` environment. It never provisions resources.

## GitHub Actions read-only Workload Identity Federation (2026-10-27)

Cloud Shell confirmation (owner): GitHub OIDC provider is **ACTIVE** at
`projects/1009769829445/locations/global/workloadIdentityPools/github-buildgce/providers/github-actions`.
Provider CEL condition requires immutable GitHub repository ID `639154288`,
owner ID `724959` and the exact branch
`refs/heads/feat/solo-gce-workstation-20261026`.
The operator then created `buildgce-auditor@argon-surf-472319-b0.iam.gserviceaccount.com`,
granted `roles/iam.workloadIdentityUser` **on that service account only**
to the repository-ID principalSet and assigned these project-scoped
read-only roles: `roles/compute.viewer`,
`roles/iam.securityReviewer`, `roles/serviceusage.serviceUsageViewer`.
No JSON key, owner/admin permission or deployment permission was added.

The dedicated workflow `.github/workflows/gce-wif-audit.yml` is triggered
by pushes of its own configuration/audit scripts on the BuildGCE branch
ONLY; it grants `id-token: write` to its own job, uses short-lived
`google-github-actions/auth@v3` credentials, installs Cloud SDK and
runs `workstations/scripts/gce-wif-readonly-audit.sh`. No manual
GitHub Secrets/variables needed. GitHub OIDC credentials are excluded
from Git by `.gitignore`. Do not add `pull_request` or expand the
branch-specific provider CEL condition. The Google identities used by
the physical Dell for IAP are separate from the GitHub auditor identity.

A **successful** WIF audit means identity exchange plus selected
read-only API checks succeeded. It does **not** mean IAP API is enabled,
the VM exists, VPC effective firewall is safe, XRDP can authenticate or
the user's 512 GiB disk has been provisioned. The audit reports
`PENDING` for incomplete deployment prerequisites and
`REVIEW` for potentially broad classic ingress; hierarchical/global
policies and actual effective per-instance firewalls remain a separate
gate. Do not publish raw project IAM policies or authentication tokens
in public GitHub Actions logs or artifacts.

Official references:
https://github.com/google-github-actions/auth
https://github.com/google-github-actions/setup-gcloud
https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines
