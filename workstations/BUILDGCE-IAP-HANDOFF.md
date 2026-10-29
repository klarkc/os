# BuildGCE -> BuildClient: IAP TCP integration contract

Canonical issue: https://github.com/klarkc/os/issues/21
Server branch: `feat/wsklarkc-gce`
Client branch: `feat/solo-thin-client-ci-20261026` (NOT modified here).

**Lifecycle v2 override:** any references below to GCE suspend/resume as
a reconnect test are historical and invalid for preserving RAM/XMonad.
Never perform stop/start as an idle/budget fallback. The required path
is a separately approved Compute Engine suspend/resume E2E in an
equivalent disposable VM, followed by real IAP/XRDP reattachment and
bidirectional audio verification. No production deployment is authorized.

## Confirmed server-side design

The `gcp-workstation.nix` image includes XRDP on TCP 3389,
Xorg/XMonad only, without XFCE or local Lemurs. NixOS nftables allows new TCP 3389
from `35.235.240.0/20` only; optional SSH/OS Login admin TCP 22
also requires the IAP CIDR. No Tailscale, WireGuard or VPN pairing.
The local graphical account is `klarkc`, and its initial password
is locked until an interactive admin runs `wsklarkc-xrdp-set-password`.
IAP authorizes a tunnel, not the XRDP username/password.

Cloud IAM, APIs and firewall cannot be called **verified** until an
actual `wsklarkc` VM has been provisioned and audited. That is
a separate cost-approval gate.

## BuildClient acceptance interface

1. Boot the Dell from Ventoy without changing its internal disk.
2. Restore stored Google Cloud credentials from its trusted Ventoy USB
   or run `gcloud auth login --no-launch-browser` on first use.
   Never embed tokens in an ISO, shell history or Git.
3. Open and keep alive the *local* tunnel:
   
   ```bash
   gcloud compute start-iap-tunnel wsklarkc 3389 \
     --project=argon-surf-472319-b0 \
     --zone=southamerica-east1-b \
     --local-host-port=localhost:13389
   ```

4. Once the tunnel actually listens, run FreeRDP:
   
   ```bash
   xfreerdp /v:127.0.0.1:13389 \
     /f /dynamic-resolution /cert:tofu /sec:tls
   ```

5. Recover on tunnel termination or VM suspend/resume without Wi-Fi or
   Google interactive reauthentication unless the Google refresh
   mechanism actually requires it. Provide a clearly visible failure
   when permissions expire or VM is not running.

## Separation of responsibilities

BuildClient owns Google OAuth persistence, IAP readiness, FreeRDP process
lifecycle, Wi-Fi recovery and the Dell boot test. BuildGCE owns IAM and
firewall preconditions, the NixOS server image and persistent VM tests.
Neither workstream should recreate VPN key exchange or use public VM
addresses as the client endpoint.

## Evidence checklist for joint closure

- Server GitHub Actions: evaluation, QEMU boot+reboot, source-restricted
  nftables rules, XRDP/sesman, Xorg/XMonad-only config, VPN absence,
  locked initial account, raw GCE image archive+SHA256
- Google Cloud: IAP API enabled, scoped IAM role conditioned for 3389,
  authenticated principal can locate VM, port-22 admin role separately,
  VPC effective firewall from `35.235.240.0/20` only, no public admin
  ingress, budget/quotas approved, persistent disk and VM RUNNING
- Real Dell: IAP tunnel on localhost:13389, actual remote port reachability,
  real XRDP graphical login, display resize and reconnect, stop/start
  persistence of `/home/klarkc/.git` and user state

Never treat CI green or `gcloud start-iap-tunnel` running as proof of
successful graphical login. No resource creation until cost approval.
