# lpklarkc — cliente NixOS Live

Esta flake isolada permite construir o cliente portátil `lpklarkc` e
testar a integração com o Google Compute Engine. Não instala nem grava
arquivos no disco interno do notebook.

## Cliente: lpklarkc

- ISO `lpklarkc-x86_64.iso` no pendrive **Ventoy existente**.
- **Não modificamos configurações, menus, timeouts ou comportamento do Ventoy.**
  O projeto e seus artefatos não incluem `ventoy.json`.
- Primeiro boot: conectar Wi-Fi por `nmtui`, verificar o USB Ventoy e
  autorizar Google **no Mozilla Firefox (official binary) do proprio notebook**.
  Uma sessao temporaria rootless Xorg + Openbox abre
  `gcloud auth login --launch-browser` com callback localhost, sem celular,
  segundo computador ou transferencia de codigo. O navegador e o cache
  existem apenas em RAM e sao removidos apos o login.
- Túnel Google IAP para o recurso GCE `wsklarkc` no projeto
  `argon-surf-472319-b0`, zona `southamerica-east1-b`, porta TCP 3389.
  FreeRDP conecta exclusivamente a `127.0.0.1:13389`.
- Notebook sem suspensão/hibernação automática: o logind ignora fechamento
  da tampa e teclas de suspensão; as operações de sleep estão desabilitadas.
  A tecla física de energia mantém o desligamento normal. Boot por Ventoy. Se VM `SUSPENDED`, cliente executa `instances.resume` e
  reanexa XRDP; se `RUNNING`, conecta; se `TERMINATED`, informa
  que a RAM anterior não existe e **não inicia** a VM automaticamente.
- Desligar o notebook não encerra agentes, builds ou aplicativos remotos.
  Quando o controlador do servidor decidir suspender com segurança,
  watchdog local aguarda confirmação repetida de `SUSPENDED` antes de
  desligar o notebook. Erros de Wi-Fi ou permissão GCE não desligam o cliente.
- Sem XFCE local, Tailscale ou WireGuard. Interface minima com NetworkManager,
  Xorg sob demanda via `startx`, Mozilla Firefox (official binary) e Openbox **somente na fase OAuth**,
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

## Empacotamento do navegador e ISO

A ISO é um **live CD x86-64 portátil**, para notebooks de vários fabricantes,
não uma imagem de instalação no disco. O navegador Google OAuth continua sendo
`firefox-bin` (binário oficial da Mozilla, única exceção permitida na política
de pacotes não livres). O cliente conserva Google Cloud CLI, IAP, FreeRDP,
PipeWire, Ventoy e configuração temporária em RAM.

A compressão do SquashFS é `xz -Xdict-size 100% -Xbcj x86`. Não removemos
firmware de Wi-Fi nem drivers gráficos essenciais somente para reduzir bytes.

## Orçamento de tamanho e verificação

O CI mede o arquivo ISO final. O antigo limite de **1152 MiB** da versão
restrita ao Dell foi substituído pelo teto rígido de **3072 MiB (3 GiB)** do
perfil genérico, que inclui firmware redistribuível amplo e Mesa. Esse teto
não é o tamanho efetivo: o CI continua bloqueando a publicação se a imagem
ultrapassar o limite e registra o tamanho medido. Não confundir
`nix flake check` com boot real: o workflow também inicializa VMs QEMU e testa
Ventoy e o ambiente gráfico antes da publicação.

A imagem inclui boot USB/CD para BIOS e UEFI, mas não substitui uma imagem
ARM64 ou uma ISO assinada para Secure Boot. Em equipamentos com Secure Boot
que não aceitam esta ISO, a configuração de firmware/boot precisará ser
ajustada pelo operador.

O Ventoy não é configurado nem alterado por este projeto.

## Inicialização sem display manager

O `tty1` faz autologin como `nixos` e abre `lpklarkc`. Wi-Fi e `nmtui`
ficam no console. Para autorizar Google, `startx` abre uma sessao rootless
com Mozilla Firefox (official binary) e Openbox minimo; `gcloud auth login --launch-browser`
usa callback localhost, sem segundo dispositivo. Ao concluir/cancelar,
essa sessao Xorg encerra e o console retoma. Apos IAP/XRDP pronto, um
outro `startx` inicia somente FreeRDP em tela cheia. `Ctrl+Alt+F2`
permanece como recuperacao local.

Para uma investigacao fisica **autorizada**, o console de recuperacao tty2
pode executar `lpklarkc --diagnose-xorg` (sem `sudo`). O comando apenas le
a sessao logind atual, os dispositivos DRM `cardN` e assinaturas do ultimo
`Xorg.0.log`; nao troca VT, inicia Xorg ou acessa tokens. O retrato atual
**nao** comprova o estado do logind no instante da falha original.
A linha `Correlacao self/seat0` compara somente IDs atuais: `DIVERGENTE`
no tty2 pode ser normal; `INDETERMINADA` nao explica o FD DRM
`paused 1` observado no Xorg anterior.


### Firmware e hardware

O perfil usa `hardware.enableAllHardware` e
`hardware.enableRedistributableFirmware`, que incluem drivers para vários
controladores de armazenamento, Wi-Fi e GPUs, em vez de selecionar arquivos
específicos do Dell. A pilha Mesa/DRM-KMS está ativa e o Xorg detecta
`modesetting`, `amdgpu`, `nouveau` (NVIDIA aberto), `intel` e `vesa`
(fallback para BIOS legado). O módulo Xorg `fbdev` problemático observado
no Dell não é uma dependência obrigatória.

O objetivo é **máxima compatibilidade razoável em notebooks x86-64**, e não
garantia literal de todos os equipamentos: firmware proprietário não
redistribuível, drivers NVIDIA proprietários, arquiteturas ARM64,
Secure Boot e GPUs/placas Wi-Fi ainda sem suporte no kernel exigem soluções
específicas. O primeiro teste Dell reportou `/dev/dri/card0` ausente,
`fbdevHWSave` incompatível e `no screens found`. A regressão
`tests/generic-live-hardware.sh` verifica que a imagem produzida não
volta a desativar o suporte amplo de hardware.
