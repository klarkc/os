# Temporary NixOS workstation

This self-contained flake does not modify the legacy root `flake.nix`.
**Canonical integration contract:** https://github.com/klarkc/os/issues/21.
Google Cloud IAP TCP replaces the old VPN integration.

## Two independent workstreams

**BuildGCE** owns the NixOS CPU-only workstation image and its firewall,
bootstrap, QEMU gates, IAM/VPC requirements and persistence. Its RDP listener
on 3389 is reachable only from IAP proxies (`35.235.240.0/20`) in the
guest nftables firewall; the GCP VPC must have matching restricted rules.
SSH port 22 is similarly restricted for OS Login administration.
See [GCE-OPERATIONS.md](GCE-OPERATIONS.md).

**BuildClient** owns the borrowed 4 GiB Dell, Ventoy persistence, Wi-Fi,
gcloud authentication and FreeRDP tunnel via `localhost:13389`. The
historical thin-client implementation established the initial IAP and
offline NixOS/QEMU/ISO checks. The Windows IAP/XRDP graphical login has
since been operator-verified; physical Dell boot remains a separate gate.
The Dell's disk must not be installed/repartitioned, and the Ventoy USB is
trusted and unencrypted by user decision. Do not store authentication in
the ISO, internal HDD, Git or CI. See [BUILDGCE-IAP-HANDOFF.md](BUILDGCE-IAP-HANDOFF.md).

## Build and test

From `workstations/`:

```bash
nix flake check
nix build .#checks.x86_64-linux.gce-workstation-security-vm
nix build .#gce-image
nix build .#thin-client-iso
```

GitHub Actions evaluates configurations, runs isolated QEMU tests and
publishes versioned ISO/GCE image archives with checksums. The cloud
image is `*.raw.tar.gz`, not the Ventoy ISO. Green CI means offline
gates passed, not Google IAM/tunnel/graphical E2E acceptance.

The planned GCE machine is `e2-highmem-4` (4 vCPU/32 GiB), with a
persistent 512 GiB `pd-balanced` boot disk. The NixOS `klarkc` account
begins with a locked password; after approved provisioning use an
authenticated IAP/OS Login SSH tty and run `sudo wsklarkc-xrdp-set-password`
before XRDP login. XMonad is the **sole** desktop: after dotfiles
bootstrap XRDP starts the user's XMonad wrapper; before checkout it
starts the NixOS-provided XMonad through D-Bus. XFCE is removed.
Lemurs is omitted because it manages local TTY logins; XRDP handles
remote PAM login and its own Xorg. No VM or IAM/VPC resources are
deployed by the workflow.

The dotfiles checkout belongs directly at `/home/klarkc/.git`, not
`/home/klarkc/dotfiles`. The bootstrap script refuses collisions.
The existing `klarkc/dotfiles#default` profile is not yet safe for
CPU-only NixOS without separate GPU/Arch-specific dependency review.

## Declarative CPU-only application baseline (GCE)

The workstation baseline requires **Brave and Enpass (P0)**. Both are part of the
versioned `gcp-workstation.nix` system package closure, together with portable
shell/developer tools and fonts. Nixpkgs unfree acceptance is restricted to
the Enpass derivation; this image does not install Arch/AUR, GPU, CUDA or vLLM
software. No manual `nix profile install`, `pacman`, `yay` or blanket
`make` is part of the deployment contract.

The dedicated GCE QEMU test checks the actual installed Brave/Enpass
executables in the guest. Browser startup inside **real XRDP/XMonad**, vault
unlock/synchronization, browser-extension/native-messaging autofill and
private-site browser authentication are separate operator-assisted acceptance
tests; no vault contents, OAuth tokens or browser profile are embedded in
NixOS, Git, CI, metadata or the image.

**Important:** a Git commit or rebuilt GCE image does not automatically
update the already-running `wsklarkc` instance. This source delta must be
deployed through a separately reviewed, in-place NixOS generation switch
without replacing its persistent disk or existing XRDP password. The direct
`/home/klarkc/.git` dotfiles checkout remains a separate conflict-guarded
bootstrap (`scripts/bootstrap-dotfiles.sh`); it must not overwrite an
existing home, activate the legacy Arch shell/desktop blindly or install the
GPU-oriented `dotfiles#default` profile. Bidirectional RDP audio is deferred.
