# lpklarkc ↔ BuildGCE: Google Cloud IAP TCP contract

**Decision 26 Oct 2026:** Google IAP TCP forwarding replaces WireGuard and
Tailscale entirely. Previous WireGuard handoff is superseded by
[issue #21](https://github.com/klarkc/os/issues/21).

## Client: lpklarkc NixOS Live ISO on trusted Ventoy USB

- GCE project: `argon-surf-472319-b0`; zone: `southamerica-east1-b`.
- GCE instance **resource name** (not just Linux hostname): `wsklarkc`.
- A one-time `gcloud auth login --no-launch-browser` opens a Google URL.
  User authorizes in a browser on another device and enters the returned
  code on the Dell. Requires no browser or second gcloud installation on Dell.
- The dedicated `CLOUDSDK_CONFIG` is
  `/home/nixos/.config/lpklarkc-gcloud`, in ephemeral RAM. The SQLite
  `credentials.db` and `configurations/config_default` are backed up to
  the **unencrypted, trusted Ventoy** USB under `lpklarkc/` as root-only exFAT files.
  `sqlite3 .backup` ensures a consistent copy during any credential refresh.
  No logs, CLI caches or ADC tokens are persisted. FreeRDP's TLS TOFU
  certificate pins are also saved and restored (FreeRDP 3 server/*.pem;
  legacy known_hosts2), preventing silent certificate acceptance each boot.
- Boot restore runs before NetworkManager; Wi-Fi profiles restore from USB.
- No configuration or secrets are written to internal Dell HDD.
- Credentials restored on subsequent boots avoid repeated login unless
  authorization is revoked or expires.
- `lpklarkc-iap tunnel` opens a TCP listener **only** at
  `127.0.0.1:13389`, connecting to GCE TCP `3389` via IAP.
- Once the tunnel confirms readiness, FreeRDP opens
  `127.0.0.1:13389` fullscreen; XRDP asks for server login.
- On disconnect the IAP process is stopped and reopened after retry.

```bash
gcloud --quiet compute start-iap-tunnel wsklarkc 3389 \
  --project=argon-surf-472319-b0 \
  --zone=southamerica-east1-b \
  --local-host-port=127.0.0.1:13389
xfreerdp /v:127.0.0.1:13389 /f /dynamic-resolution /cert:tofu /sec:tls
```

## Server: BuildGCE responsibilities (separate branch)

- IAP API enabled and principal granted minimum roles for TCP tunnel and
  reading the instance; IAM principal is identified at first OAuth login.
- Firewall VPC allows only TCP 3389 from `35.235.240.0/20` to workstation;
  NixOS firewall must allow that IAP source.
- Keep XRDP, XMonad with XFCE fallback, and persistent `klarkc` home.
- XRDP user password provisioned through authenticated administrative path.
  IAP authentication does NOT replace XRDP login.
- No publicly exposed RDP, no WireGuard peer config, no UDP 51820, no
  Tailscale account and no public static IP requirement.
- With no public VM IP, ordinary outbound internet may require NAT and cost;
  evaluate before provisioning.

## Security

The unencrypted USB will contain a **gcloud user OAuth refresh credential**.
It is *not* a `compute.readonly`-restricted ADC token, and inherits the
permissions granted to the authenticated Google identity. Physical theft
can expose those permissions until revocation. Strongly prefer granting the
Google login principal only the minimal IAM required for IAP and instance
discovery; avoid using an owner/admin identity when possible. The user
explicitly chose a trusted USB without encryption.

No Google credentials or cloud resources are involved in QEMU CI. CI
proves USB Wi-Fi and CLI SQLite config persistence across a real guest
reboot and offline IAP command arguments. Real Google login, real IAP
authorization, actual RDP and Dell firmware/Wi-Fi are separate E2E gates.

Official references:
- https://docs.cloud.google.com/sdk/docs/authenticate
- https://docs.cloud.google.com/iap/docs/using-tcp-forwarding
- https://docs.cloud.google.com/sdk/gcloud/reference/compute/start-iap-tunnel

## Identidade e boot

- Cliente: hostname e identidade `lpklarkc`.
- Destino IAP: **nome do recurso** Compute Engine `wsklarkc`, não apenas
  o hostname do sistema operacional.
- BuildGCE deverá configurar também o hostname Linux como `wsklarkc`,
  em sua própria branch. Este trabalho **não altera** o servidor.
- BuildClient não cria nem distribui `ventoy.json` e **não modifica**
  menus, seleção ou opções do Ventoy existente.
- Diretório de persistência novo `lpklarkc/` não migra automaticamente
  estado de versões anteriores, preservando arquivos preexistentes.
