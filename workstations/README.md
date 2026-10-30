# lpklarkc — cliente NixOS Live

Esta flake isolada permite construir o cliente portátil `lpklarkc` e
testar a integração com o Google Compute Engine. Não instala nem grava
arquivos no HDD do Dell.

## Cliente: lpklarkc

- ISO `lpklarkc-x86_64.iso` no pendrive **Ventoy existente**.
- **Não modificamos configurações, menus, timeouts ou comportamento do Ventoy.**
  O projeto e seus artefatos não incluem `ventoy.json`.
- Primeiro boot: conectar Wi-Fi por `nmtui`, verificar o USB Ventoy e
  autorizar Google **no Firefox ESR do proprio Dell**.
  Uma sessao temporaria rootless Xorg + Openbox abre
  `gcloud auth login --launch-browser` com callback localhost, sem celular,
  segundo computador ou transferencia de codigo. O navegador e o cache
  existem apenas em RAM e sao removidos apos o login.
- Túnel Google IAP para o recurso GCE `wsklarkc` no projeto
  `argon-surf-472319-b0`, zona `southamerica-east1-b`, porta TCP 3389.
  FreeRDP conecta exclusivamente a `127.0.0.1:13389`.
- Dell sem suspensão/hibernação automática: o logind ignora fechamento
  da tampa e teclas de suspensão; as operações de sleep estão desabilitadas.
  A tecla física de energia mantém o desligamento normal. Boot por Ventoy. Se VM `SUSPENDED`, cliente executa `instances.resume` e
  reanexa XRDP; se `RUNNING`, conecta; se `TERMINATED`, informa
  que a RAM anterior não existe e **não inicia** a VM automaticamente.
- Desligar Dell não encerra agentes, builds ou aplicativos remotos.
  Quando o controlador do servidor decidir suspender com segurança,
  watchdog local aguarda confirmação repetida de `SUSPENDED` antes de
  desligar o Dell. Erros de Wi-Fi ou permissão GCE não desligam o cliente.
- Sem XFCE local, Tailscale ou WireGuard. Interface minima com NetworkManager,
  Xorg sob demanda via `startx`, Firefox ESR e Openbox **somente na fase OAuth**,
  e FreeRDP. Nao ha LightDM, Xterm, desktop completo nem WM persistente.
- Áudio bidirecional via PipeWire + WirePlumber no cliente, usando
  `pipewire-pulse` para o backend PulseAudio do FreeRDP:
  `/sound:sys:pulse /microphone:sys:pulse`. O XRDP expõe dispositivos
  virtuais de reprodução e microfone no servidor (não os IDs físicos do Dell).
  Nenhum túnel adicional nem daemon PulseAudio legado é necessário.
- Wi-Fi, credenciais CLI Google e certificados TLS são salvos somente em
  `lpklarkc/` na partição de dados do Ventoy, montada em
  `/run/lpklarkc/ventoy`. USB confiável **sem criptografia** conforme decisão.
- Recuperacao sem tocar no HDD: `nmtui`, `lpklarkc-state diagnose`,
  `sudo -n lpklarkc-state ensure` e `sudo -n lpklarkc-state is-ready`.
  A ultima permissao e somente leitura para validar o USB root-only,
  nao uma liberacao de sudo geral.

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

## Orçamento de tamanho

A ISO usa `iso-image.nix` + `minimal.nix` e não importa o perfil de
instalação, Nixpkgs channel, ferramentas de particionamento/recuperação
ou manual. Também desativa o daemon Nix e o registro de flakes **no
cliente**, mantendo o Nix normalmente disponível no ambiente CI que
compila a ISO. Nenhum pacote é instalado no Dell durante a execução. BIOS/UEFI, drivers e firmware continuam disponíveis para o Dell.

O CI mede o **arquivo ISO final**, impondo **1024 MiB (1 GiB)** como
limite, apos a ISO anterior de 1.034.944.512 bytes (987 MiB arredondados).
  Firefox ESR e um requisito funcional novo e pode ultrapassar o limite:
  o CI nao o eleva silenciosamente. Em caso de excesso, reportar o valor
  real ao Coordinator para decisao. `tests/iso-size-budget.sh --self-test` prova que aceita o
limite exato e rejeita um byte excedente. Compilação e distribuição
continuam condicionadas aos testes QEMU.

O Ventoy não é configurado nem alterado por este projeto.

## Inicialização sem display manager

O `tty1` faz autologin como `nixos` e abre `lpklarkc`. Wi-Fi e `nmtui`
ficam no console. Para autorizar Google, `startx` abre uma sessao rootless
com Firefox ESR e Openbox minimo; `gcloud auth login --launch-browser`
usa callback localhost, sem segundo dispositivo. Ao concluir/cancelar,
essa sessao Xorg encerra e o console retoma. Apos IAP/XRDP pronto, um
outro `startx` inicia somente FreeRDP em tela cheia. `Ctrl+Alt+F2`
permanece como recuperacao local.

### Firmware e hardware

A ISO contém drivers de boot USB/ISO e firmware direcionado ao Dell Inspiron
i14-5458-D08P: vídeo Intel HD Graphics 5500/Broadwell e WLAN Qualcomm 9565 /
Dell Wireless 1707, com fallback Intel 3160/7265, Broadcom, Realtek e QCA
de geração próxima. Não embute firmware de Wi-Fi 6E/7 e GPUs modernas que
não pertencem a esse notebook. O Google CLI e o FreeRDP permanecem completos.
A PCI ID real do adaptador do Dell e o áudio físico ainda exigem teste de
aceitação; substituições posteriores da placa Wi-Fi podem exigir firmware
adicional. Não utilizar esta ISO enxuta como imagem genérica para outros PCs.
