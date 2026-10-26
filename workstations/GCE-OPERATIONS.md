# NixOS GCE workstation: import and operations

This is a **runbook, not an authorization** to provision billable resources.

## Build gates

The `gce-image` GitHub Actions job runs only after Nix evaluation and the
QEMU VM tests. It uploads a `*.raw.tar.gz` with SHA256SUMS, retained for
seven days; the CI job does **not** import the image or create an instance.
Confirm the completed run and download the artifact before proceeding.
A QEMU VM test verifies host services; it does **not** prove GCE metadata,
OS Login, IAP or a real XRDP desktop session.

## One-time import (requires explicit budget approval)

- Project: `argon-surf-472319-b0`; candidate zone: `southamerica-east1-b`.
- Candidate shape: `e2-highmem-4` (4 vCPU / 32 GiB), CPU only.
- Candidate boot disk: 150 GiB `pd-balanced`, **persistent and retained on VM stop**.
- Compute billed while running (including idle); disk billed while stopped.
  Network egress, image storage, snapshots and public/static IPv4 may cost extra.
  Obtain a fresh Google Cloud Pricing Calculator estimate for 172 h/month,
  storage for 730 h/month, quota and billing alerts before approval.

After approval, upload the verified `*.raw.tar.gz` image to a private
Cloud Storage bucket. Create a custom Compute Engine image from that
object using `gcloud compute images create NAME --source-uri=gs://BUCKET/IMAGE.raw.tar.gz`.
Use the raw disk archive, **not** an ISO or Debian source image.
Provision with the custom image and a persistent boot disk; set
`enable-oslogin=TRUE` on instance metadata. Prefer `--no-address` on
the VM NIC. Do not open public TCP 3389. For SSH bootstrap without a
public IP, arrange IAM OS Login and IAP TCP forwarding (source range
`35.235.240.0/20` to TCP 22) with least-privilege permissions.
The OS Login account can differ from `klarkc`; check this explicitly.

## First login and access

1. Verify GCE serial boot/agent and SSH via OS Login/IAP. Do not claim it
   works solely because `security.googleOsLogin.enable` evaluates.
2. Connect Tailscale interactively (`sudo tailscale up`) in the VM.
   Keep tailnet credentials out of image, metadata and CI logs.
3. Via the authenticated SSH shell, set `klarkc`'s password securely
   using `sudo passwd klarkc` in a real interactive terminal. Do not
   pass a password via arguments or store a hash in the repository.
   This enables XRDP; SSH remains key-only. Review whether `klarkc`
   should have interactive sudo access before use.
4. From the Dell in the tailnet, connect to `solo-workstation:3389`.
   Check Xorg/XRDP login, XMonad fallback to XFCE, keyboard layout,
   clipboard, display resize and reconnection. Tailscale is the sole
   permitted RDP ingress interface on the guest firewall. Also check
   the GCE VPC rules do not expose 3389.
5. Run `bash workstations/scripts/bootstrap-dotfiles.sh` as `klarkc`
   from a separate checkout of `klarkc/os`. It aborts on collisions.
   `/home/klarkc/.git` must become the dotfiles checkout; **do not**
   install `klarkc/dotfiles#default` as-is: it includes GPU/vLLM
   and machine-specific assumptions. Review a CPU-only profile first.

## Stop/start and persistence validation

Write a uniquely named file inside `/home/klarkc`; stop the VM with
`gcloud compute instances stop NAME --zone=southamerica-east1-b`
(or Compute Engine API), and verify status `TERMINATED`. Check the
persistent disk still exists. Start it, reconnect through OS Login and
Tailscale, and verify the file, `/home/klarkc/.git`, passwords and
graphical profile survive. Capture operation `DONE`, logs and evidence.

Stopping a VM does not automatically delete disk, snapshots or images.
Do not configure automatic start/stop schedules without permission.
If a provision operation fails, preserve the boot disk and diagnostic
logs; avoid deleting the disk as a cleanup shortcut.
