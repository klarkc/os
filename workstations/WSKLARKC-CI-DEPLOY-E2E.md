# wsklarkc — GitHub Actions deploy + real GCE integration + authenticated XRDP E2E

**Owner:** BuildGCE, exclusively `feat/wsklarkc-gce`.

> **Lifecycle v2 and budget HOLD (2026-10-29):** The historically specified
> GCE stop/start acceptance **is invalid** because it loses RAM, processes and
> the original XRDP/XMonad session. The `gce-stop-start` job and script are
> disabled. **Do not trigger production deploy**: catalog cost of the planned
> 512 GiB `pd-balanced` disk alone is about R$455.50/month, exceeding the
> R$400 reference. Obtain an explicit new decision on shape/storage/cost
> and an approved, equivalent disposable-VM suspend/resume E2E first.
> All live jobs remain disabled pending explicit approval.

**Separate client branch:** BuildClient owns `feat/lpklarkc-ci-20261029`.
No edits to the Dell's NixOS image, Ventoy scripts, Wi-Fi state or its CI.
The shared integration is Google IAP TCP, no VPN or public RDP.

## Contract and resource names

| Item | Expected |
| --- | --- |
| Project / number | `argon-surf-472319-b0` / `1009769829445` |
| Zone | `southamerica-east1-b` |
| VM name and NixOS hostname | `wsklarkc` |
| CPU / RAM | `e2-highmem-4`, 4 vCPU / 32 GiB |
| Disk | **512 GiB** boot `pd-balanced`, `autoDelete=false`, persistent through suspension |
| VPC / subnet | `wsklarkc-iap-vpc` / `wsklarkc-iap-subnet` |
| IAP ingress | TCP 22 and TCP 3389 only from `35.235.240.0/20` |
| Guest firewall | nftables duplicates same IAP CIDR restriction |
| Desktop | XRDP + Xorg + **XMonad only**; no XFCE/Lemurs |
| GPU | None, CUDA and vLLM disabled |
| Public IP | None on initial deployment; later egress requires independent effective-firewall check |
| Boot firmware | Legacy/MBR from pinned NixOS GCE image; no Shielded VM vTPM until separate UEFI/GPT migration and boot tests |
| Client flow | IAP TCP → localhost `127.0.0.1:13389` → FreeRDP → authenticated XRDP/XMonad |
| Test account | `wsklarkcci` created only for CI E2E and deleted in cleanup |

**Historical cost approval:** user previously authorized a single VM and
512-GiB disk, but the new BRL cost study showed that this plan exceeds the
current R$400 reference even when suspended all month. **NO-GO** for paid
provisioning until the user chooses a revised plan; never change disk size
or type in the provisioner without explicit agreement. This is NOT an approval for Cloud NAT, reserved static IP, GPU, VPN,
other VMs, or unbounded operation. Disks and imported custom images
continue to incur storage charges while the VM is suspended.

## One-time Cloud Shell authorization (required)

The existing `buildgce-auditor` is **read-only** and the connected GCE
create-instance API cannot choose the custom NixOS image, disk type,
capacity, retained disk or private VPC. The existing auditor cannot
grant IAM roles to another service account. The ONE required
human-administrative bootstrap configures short-lived GitHub OIDC.

Open Google Cloud Shell as the authorized project administrator:

```bash
gcloud config set project argon-surf-472319-b0
git clone --single-branch --branch feat/wsklarkc-gce \
  https://github.com/klarkc/os.git ~/os-wsklarkc
cd ~/os-wsklarkc
bash workstations/scripts/gce-ci-iam-bootstrap.sh
```

The bootstrap:
1. **Replaces** the old auditor pool condition with the new exact
   `feat/wsklarkc-gce` branch (not an OR with the old branch). The
   auditor retains its three read-only roles.
2. Creates a separate WIF pool/provider condition requiring immutable
   repository ID `639154288`, owner ID `724959`, the exact
   `refs/heads/feat/wsklarkc-gce` and the specific trusted
   `.github/workflows/build-thin-client.yml` GitHub workflow ref.
3. Creates `buildgce-deployer` and `buildgce-e2e` service accounts
   with short-lived `roles/iam.workloadIdentityUser` on their
   **own** accounts, no JSON keys and no GitHub Secrets.
4. Grants the deployer project-scoped roles needed for image import,
   VPC/firewall, VM creation/lifecycle and instance-specific IAP IAM:
   `compute.instanceAdmin.v1`, `compute.networkAdmin`,
   `compute.securityAdmin`, `storage.admin`, `iap.admin`.
   **These roles are broad within the project, so review and revoke
   after one-time provisioning if ongoing CI deployments are not desired.**
   The test identity gets project `compute.viewer` only initially;
   the deploy job later grants OS Admin Login on the single VM and
   IAP tunnel access conditioned to TCP ports 22 and 3389.
5. Verifies the WIF conditions. It does not create any paid VM,
   disk, Cloud NAT, public IP or custom image.

If this operation fails, retain the full error **without copying
tokens or JSON credentials**. A Github Actions build cannot fix an
initial missing project IAM grant with the read-only auditor.

## Real pipeline order (server branch only)

The trusted `.github/workflows/build-thin-client.yml` now has
these **blocking jobs**, after the existing NixOS evaluation,
QEMU boot/reboot/persistence, ISO and custom GCE image gates:

1. **Deploy:** WIF as deployer; verify that the image artifact belongs
   to the **same successful run and SHA**, and its SHA256 checksum;
   create dedicated VPC, IAP-only rules, a short-lived private import
   bucket and exactly one NixOS `wsklarkc` VM with a retained
   512 GiB disk, without any public IP. Repeated runs refuse
   replacement of an existing VM/disk.
2. **Production integration:** WIF as verifier; query **live**
   instance/image/disk metadata, exact machine type, absence of GPU,
   no VM attached service account, dedicated VPC/subnet, exact firewall
   tags/rules, **effective** ingress and absence of public address.
   Unexpected ingress or inherited policy: **fail**.
3. **Authorize E2E:** grant the `buildgce-e2e` service account
   OS Admin Login on the single VM and instance-specific IAP
   tunnel access to TCP 22 and 3389 (not project-wide tunnel access).
4. **Authenticated login:** fresh `wsklarkcci` test user/password
   generated in the ephemeral GitHub runner. Via Google IAP port 22
   the test configures guest credential over SSH **stdin**, never
   argv, CI logs, Git, metadata or Nix store. It opens
   `gcloud compute start-iap-tunnel wsklarkc 3389` bound only to
   `127.0.0.1:13389`, then starts FreeRDP 3 over TLS TOFU in
   Xvfb, with the password via `/from-stdin:force`. A remote
   privileged probe **requires a process named `xmonad` owned
   by `wsklarkcci` with an Xorg `DISPLAY`**. An opened TCP
   socket alone NEVER passes.
5. **BLOCKED legacy gate:** Real stop/start is **not run** because it
   destroys the running process/RAM state. Replacing this gate requires
   `instances.suspend` / `instances.resume` on a separately approved
   *disposable equivalent VM*, confirming identical boot ID, XMonad PID,
   session DISPLAY, sentinel in RAM and agent/tmux PIDs.
6. **Authenticated reconnection (BLOCKED):** after the replacement
   suspend/resume gate, reconnect via IAP and verify the **same existing**
   XMonad process/session (not just a new login and persisted HOME marker).
   Verify `xrdp-sink`/`xrdp-source` and real playback/microphone separately.
7. **Always-cleanup (after authorization):** remove only temporary
   `wsklarkcci`, its HOME and temporary test script. Real `klarkc`
   HOME, private secrets and dotfiles are never touched.
8. **Production acceptance:** succeeds only when ALL these
   production jobs report success, including cleanup. No job may
   replace authenticated XRDP with an unsecured port scan.

Production deployment is **manual opt-in only** via `workflow_dispatch`
on `feat/wsklarkc-gce` with `approve_production_deploy=true`, AND remains
**NO-GO** until renewed budget approval and lifecycle E2E redesign. Ordinary
pushes run offline tests and image builds, not paid cloud changes.
WIF is used only for authorized production jobs.
No production job is allowed to run against main/BuildClient.
CI concurrency does not cancel mid-deployment operations.

## Independent acceptance still required

A CI E2E user and a headless FreeRDP session are a functional
equivalent of the client IAP connection and remote graphical login,
**NOT** proof that the physical Dell keyboard, Wi-Fi/USB state,
saved OAuth refresh token or display works. The BuildClient agent
owns those tests.

A separate authorized administrative login must still set the
personal XRDP password for `klarkc` using an interactive TTY:
`sudo wsklarkc-xrdp-set-password`. The CI must never store, reset or
read that personal password. The Dell's Google identity must receive
a scoped IAP/instance-viewer binding separate from the CI E2E
identity. Afterwards, restore `klarkc/dotfiles` directly into
`/home/klarkc`, separately recover private state and validate the
SoloSIG Nix/devenv workloads; do not enable GPU, CUDA or local vLLM.

**Current status** (until proved otherwise): code and tests prepared,
actual Cloud Shell bootstrap and billable VM deployment **pending**.
Do not close issue #21 based on QEMU CI or WIF read-only audit alone.

Official documentation:
- https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines
- https://docs.cloud.google.com/iap/docs/using-tcp-forwarding
- https://docs.cloud.google.com/compute/docs/oslogin/set-up-oslogin
- https://docs.cloud.google.com/compute/docs/reference/rest/v1/instances/getEffectiveFirewalls
