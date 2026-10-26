# Temporary Solo workstation (NixOS)

This is an isolated flake. It does not modify the legacy root flake.

## Client (Dell laptop, 4 GiB)

- Boot an ISO from the existing Ventoy USB. **Do not install NixOS** or repartition the borrowed laptop.
- Requires Ventoy's writable data partition to be labelled `Ventoy` and exposed as a USB block device. Only this exact USB device will be mounted.
- On the first boot, enter the Wi-Fi password in `nmtui`, then authenticate Tailscale using a browser on your phone.
- The client saves NetworkManager `*.nmconnection` files and `tailscaled.state` to `Ventoy/solo-client/` every minute. This data is **unencrypted** and can be read by anyone with access to the USB drive; the owner has explicitly accepted this.
- Later boots restore both pieces of state before starting NetworkManager/Tailscale and reconnect RDP automatically. No local login or repeated Wi-Fi typing.
- The RDP server login screen (not the borrowed laptop) asks for your workstation account.
- The remote host defaults to `solo-workstation` through Tailscale DNS. To override once, in a local terminal run `sudo solo-client-state set-host HOSTNAME`.
- Recovery after a Wi-Fi change: `nmtui`; then `sudo solo-client-state save`.
- No private key, SSID, password, Tailscale auth token or account ID is committed to public GitHub.

**Security / limitations:** Ventoy state is plaintext as requested. Treat a lost USB as compromise of the Wi-Fi and tailnet identity: revoke the lost node at Tailscale and rotate the Wi-Fi credentials if warranted. The ISO cannot guarantee restoration if Ventoy's partition was renamed or formatted as an unsupported filesystem. The user must remain booted from the USB; do not use a copy-to-RAM mode. The first boot/pairing is not zero-touch.

## Build

Run from `workstations/` with Nix:

```bash
nix flake check
nix build .#thin-client-iso
nix build .#gce-image
```

GitHub workflow `Build disposable NixOS thin client` publishes an artifact only after the ISO build succeeds. A green workflow is not a substitute for boot-testing hardware and Wi-Fi.

## Server (GCE, no GPU)

The independent `gcp-workstation` configuration builds a boot image for Google Compute Engine. **32 GiB RAM is a cloud instance setting**, not an image property; plan `e2-highmem-4` (4 vCPU / 32 GiB) and a persistent boot disk. RDP is exposed only through Tailscale; do not add a public ingress firewall rule for 3389. Initially enable Google OS Login and SSH key access; set a server account password securely **only on the machine** before attempting RDP login.

After provisioning, as user `klarkc`, execute `bash workstations/scripts/bootstrap-dotfiles.sh` from a private checkout of this repository. The bootstrap clones `klarkc/dotfiles` **directly into `$HOME`** and refuses to overwrite an existing home Git checkout. Arch-specific desktop/GPU packages in `klarkc/dotfiles` still require a CPU-only NixOS migration before the full profile can be installed; no claim that this has already been completed.

No cloud instance has been provisioned, and this ISO has **not** yet been built or verified on the Dell. Do not infer a downloadable ISO from the presence of source files.
