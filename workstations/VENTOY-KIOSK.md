# Solo Workstation — Ventoy USB

O thin client roda da ISO NixOS; **nenhum Linux ou desktop será instalado no HDD**.
O cliente tem somente Xorg + Openbox + Xterm (fullscreen) + FreeRDP.
O XFCE está **somente no servidor GCE**.

## Aplicar à unidade USB no Windows

1. Extraia a nova ISO do artefato do GitHub Actions e confira SHA-256 pelo
   arquivo `SHA256SUMS` (não compare com o SHA do ZIP).
2. Na **partição de dados maior** do Ventoy, coloque
   `solo-thin-client-x86_64.iso` na raiz.
3. Copie `ventoy.json` para `ventoy/ventoy.json` nessa mesma partição
   (crie a pasta `ventoy` se não existir). **Não toque na pequena VTOYEFI**.
4. Se já houver `ventoy/ventoy.json`, mescle os itens do array `control`
   e `menu_alias`; **não sobrescreva configurações existentes**.
5. Inicialize o Dell via USB em modo normal, não copie ISO para a RAM.

O Ventoy aguarda somente 2 segundos no menu principal e seleciona a ISO.
O segundo menu Ventoy é desativado; a ISO tem timeout de 1 segundo.
Ventoy ainda mantém opções de recuperação pelo menu/funções de teclado.

O item `VTOY_LINUX_REMOUNT=1` ativa a compatibilidade para tornar
acessível a partição que contém a ISO após o boot. O cliente também pode usar
`/dev/mapper/VentoyPart` (Ventoy recente) ou localizar a partição de dados
pela partição-irmã `VTOYEFI`, verificando que o dispositivo é realmente USB.

**Importante:** Ventoy permite nome e localização diferentes para a ISO.
Nesse caso, modifique os caminhos `VTOY_DEFAULT_IMAGE` e `menu_alias.image`
para corresponder exatamente ao arquivo na sua unidade.

O USB é confiável **mas não criptografado**, por escolha do proprietário:
Wi-Fi, login gcloud e certificados FreeRDP ficam acessíveis fisicamente.

## Diagnóstico / recuperação

A tela de entrada exibe apenas "Solo Workstation". Se não conectar:
- NetworkManager Wi-Fi: `nmtui` (aberto automaticamente quando necessário).
- USB: o cliente tenta remontar novamente com regras que **não permitem
  montar um disco interno** como persistência.
- Suporte avançado: console `Ctrl+Alt+F2`; `lsblk -o NAME,TRAN,FSTYPE,LABEL,TYPE`,
  `ls -l /dev/mapper/VentoyPart` e `journalctl -u solo-ventoy-state`.
- O uso de IAP exige conta Google autorizada e servidor GCE pronto;
  testes offline não comprovam conexão real.

## Regressões obrigatórias no CI

- QEMU boot+USB físico emulado exFAT+VTOYEFI.
- Recuperação de montagem após falha no boot (teste *red* registrado).
- USB com partição de dados renomeada: descoberta via VTOYEFI.
- Partição via device-mapper VentoyPart (ancestral USB verificado).
- Perfil Wi-Fi, credencial gcloud e certificado TLS preservados após
  reinicialização **real** do kernel.
- Novo comando `ensure` e sudo estritamente limitado;
  nenhum armazenamento no disco interno e nenhum Tailscale/WireGuard.
- Inicialização automática/tema neutro; artefato da ISO somente após gates.

Documentação de referência:
- https://www.ventoy.net/en/plugin_control.html
- https://www.ventoy.net/en/doc_linux_remount.html
- https://ventoy.net/en/doc_disk_layout.html
