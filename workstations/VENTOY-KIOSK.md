# lpklarkc — boot pelo Ventoy existente

O cliente é uma ISO NixOS Live e não instala NixOS no HDD.
XFCE é opção do servidor, não do Dell.

## Atualizar no Windows

1. Extraia o ZIP do CI e valide o SHA-256 com `SHA256SUMS`.
2. Copie `lpklarkc-x86_64.iso` para a partição de dados do Ventoy.
3. Selecione a imagem **pelo menu do Ventoy que você já utiliza**.
   Não reinstale nem reconfigure o Ventoy por causa deste projeto.

Este projeto não produz nem modifica `ventoy.json`.
Se você aplicou opções desse arquivo fornecidas em versões anteriores,
remova **somente aquelas opções**, preservando outras configurações suas
ou de outras ISOs.

O cliente nao utiliza LightDM, Xterm nem ambiente desktop completo.
O Wi-Fi fica no console; Google OAuth usa Firefox ESR e Openbox minimo
numa sessao rootless `startx` temporaria **antes** do tunel IAP.
Ao autenticar, Firefox e cache/cookies efemeros sao encerrados, e outra
sessao rootless Xorg inicia FreeRDP somente apos IAP/XRDP.
Nenhum segundo dispositivo e necessario.

A aparência de `lpklarkc` muda **dentro da ISO**; o menu,
timeout e opções do Ventoy permanecem integralmente sob seu controle.

## Persistência

A imagem salva Wi-Fi, credenciais CLI Google e certificados FreeRDP em
`lpklarkc/` na partição USB de dados, sem criptografia.
Diretório em RAM para o gcloud: `/home/nixos/.config/lpklarkc-gcloud`.

Se a partição de dados estiver ocupada pela ISO, o cliente tenta montar
o mesmo dispositivo USB validado via device-mapper. O dispositivo
`/dev/mapper/ventoy` com a ISO `iso9660` não serve para guardar estado.
Em montagens tardias, `lpklarkc-state ensure` também restaura as
credenciais já salvas.

O diretório de persistência anterior não é migrado automaticamente.

## Recuperação

- Wi-Fi: `nmtui`.
- Console: `Ctrl+Alt+F2`.
- Diagnóstico: `lpklarkc-state diagnose`.
- Remontagem/restauracao: `sudo -n lpklarkc-state ensure`.
- Precheck root-only (somente leitura): `sudo -n lpklarkc-state is-ready`.
  A regra NOPASSWD e restrita a este comando, sem sudo amplo.
- Logs: `journalctl -u lpklarkc-ventoy-state`.

O CI prova persistência, reboot e falhas de montagem no QEMU; ainda
é necessário validar no Dell e conectar ao GCE real `wsklarkc`.
