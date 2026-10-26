# BuildClient -> BuildGCE integration contract (26 Oct 2026)

This branch migrates the USB NixOS Dell thin client from managed Tailscale to
self-hosted WireGuard with **read-only GCE API discovery**. It does not provision
the server or authorize new cloud spend.

## Identity and discovery

- GCE project: `argon-surf-472319-b0`.
- GCE zone: `southamerica-east1-b`.
- **GCE instance resource name**: `solo-workstation` (must match; is not just
  the Linux `networking.hostName`).
- On first boot, `nixos` runs
  `gcloud auth application-default login --no-launch-browser --disable-quota-project --scopes=https://www.googleapis.com/auth/compute.readonly`.
  Subsequent boots restore just the ADC JSON to the volatile user home from
  the trusted unencrypted Ventoy USB.
- Client queries `compute.instances.get` (IAM permission required), checks
  `RUNNING`, finds the ephemeral external `natIP`, and reads instance
  metadata item `solo-wg-server-public-key` (WireGuard public key, not secret).
- If the VM is stopped, the IP is absent, metadata is absent, or API auth is
  rejected, the client fails closed and retries. No DDNS or static IPv4 is
  required.

## WireGuard / RDP compatibility

| Setting | Dell client | GCE server |
| --- | --- | --- |
| Interface | `solo-wg` | `solo-wg` |
| Tunnel address | `10.77.0.2/32` | `10.77.0.1/24` |
| Tunnel port | outgoing UDP | listening UDP `51820` |
| Peer allowed IPs | `10.77.0.1/32` | `10.77.0.2/32` |
| Persistent keepalive | 25 seconds | optional |
| RDP | FreeRDP fullscreen to `10.77.0.1:3389` | XRDP on 3389, reachable only via WireGuard |

GCE provisioning MUST:
1. Create a persistent server WireGuard private key (never in Git, baked
   image, instance metadata, logs or public artifacts).
2. Publish its **public key** in instance metadata as
   `solo-wg-server-public-key` before the client tries to connect.
3. Configure server peer with the Dell **public** key
   (`sudo solo-client-state wg-public` on Dell after first boot).
4. Permit inbound UDP `51820` through the GCE VPC firewall; permit TCP
   `3389` **only on the server's WireGuard interface**. No internet-facing
   3389 or public SSH password authentication.
5. Configure XRDP user `klarkc` securely. RDP login uses server credentials,
   NOT the Google OAuth token.
6. Verify VM stop/start updates its ephemeral IP and client reconnects.

### Pairing boundary

Google OAuth `compute.readonly` can *read* a server public key but **cannot
register the Dell public key in the server**. A secure one-time peer registration
is still required, either by BuildGCE/admin over an authenticated management
channel or through an intentionally designed, authenticated enrollment
endpoint. Do not silently grant metadata-write/admin permissions to the
unencrypted USB credential.

## Privacy and testing

- Ventoy must be an actual USB device with label `Ventoy`; do not mount or
  format the Dell HDD. Both the OAuth refresh credential and private WG key
  reside on this **unencrypted** trusted USB; physical loss is a credential
  compromise. The Google grant can be revoked in Google account settings.
- `solo-gce-endpoint parse` is a pure offline parser for QEMU fixture JSON;
  CI MUST NOT use real Google auth or store secrets.
- The QEMU USB test must pass actual guest reboot and restore Wi-Fi, restricted
  ADC fixture and WireGuard identity, then reject invalid GCE responses.
- Physical Dell Wi-Fi and real GCE WireGuard/RDP E2E remain separate acceptance
  gates, not implied by a green QEMU CI.
