# lpklarkc — cliente NixOS Live

Esta flake isolada permite construir o cliente portátil `lpklarkc` e
testar a integração com o Google Compute Engine. Não instala nem grava
arquivos no HDD do Dell.

## Cliente: lpklarkc

- ISO `lpklarkc-x86_64.iso` no pendrive **Ventoy existente**.
- **Não modificamos configurações, menus, timeouts ou comportamento do Ventoy.**
  O projeto e seus artefatos não incluem `ventoy.json`.
- Primeiro boot: conectar Wi-Fi por `nmtui` e autorizar Google com
  `gcloud auth login --no-launch-browser` usando um navegador em outro dispositivo.
- Túnel Google IAP para o recurso GCE `wsklarkc` no projeto
  `argon-surf-472319-b0`, zona `southamerica-east1-b`, porta TCP 3389.
  FreeRDP conecta exclusivamente a `127.0.0.1:13389`.
- Sem XFCE local, Tailscale ou WireGuard. Interface mínima com NetworkManager,
  Xorg, Openbox, Xterm e FreeRDP.
- Wi-Fi, credenciais CLI Google e certificados TLS são salvos somente em
  `lpklarkc/` na partição de dados do Ventoy, montada em
  `/run/lpklarkc/ventoy`. USB confiável **sem criptografia** conforme decisão.
- Recuperação sem tocar no HDD: `nmtui`, `lpklarkc-state diagnose` e
  `sudo -n lpklarkc-state ensure`.

**Migração:** o novo diretório `lpklarkc/` e o novo
`~/.config/lpklarkc-gcloud` não importam automaticamente credenciais
guardadas sob uma identidade anterior. Pode ser necessário reconfigurar
Wi-Fi e autorizar Google uma vez. Dados anteriores não são apagados.

## Build e CI

```bash
cd workstations
nix flake check
nix build .#lpklarkc-iso
```

O workflow `.github/workflows/build-thin-client.yml` valida NixOS,
executa testes QEMU com USB emulado, falhas de montagem e reboot real,
e publica apenas ISO e `SHA256SUMS`. A conexão IAP e o XRDP reais
exigem teste separado.

## Contrato com BuildGCE

O cliente se conecta ao **nome do recurso GCE** `wsklarkc`, que não é
necessariamente alterado quando se troca somente o hostname Linux.
BuildGCE deve assegurar que **ambos** passem a ser `wsklarkc`.

Não modificamos a configuração do servidor nem provisionamos recursos
GCE nesta branch do cliente. IAM, firewall, XRDP, usuário remoto
`klarkc` e persistência do servidor são responsabilidade do BuildGCE.

Mais detalhes: [contrato IAP](./CLIENT-IAP-GCE-CONTRACT.md) e
[uso do Ventoy](./VENTOY-KIOSK.md).
