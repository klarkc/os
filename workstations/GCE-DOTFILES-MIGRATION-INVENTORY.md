# Current decision (2026-10-29): 256 GiB pd-balanced and R$560/month replace the old 512 GiB/R$400 design. Historical measurements and comparisons below are preserved only as migration evidence. No GCE provisioning is authorized.

# Inventory: solo098 Arch Linux dotfiles to CPU-only NixOS GCE

**Evidence date:** 2026-10-27. Source snapshot: [klarkc/dotfiles main at
`0f2dbfda51d57a0539317a1ef7c1ff084c5513db`](https://github.com/klarkc/dotfiles/tree/0f2dbfda51d57a0539317a1ef7c1ff084c5513db).
Target: [BuildGCE branch](https://github.com/klarkc/os/tree/feat/wsklarkc-gce),
`workstations/gcp-workstation.nix`, NixOS x86_64, **no GPU**. Canonical
IAP interface: [issue #21](https://github.com/klarkc/os/issues/21).

This is a **source-level inventory**, not an audit of the original
solo098 machine's installed package database or untracked HOME data.
The old machine was sanitized; neither running services nor private
runtime secrets have been recovered/validated on GCE. Package names
below are proposed Nixpkgs equivalents, **not a claim that all
derivations or graphical workflows have already been built or tested**.

## Storage contract (revised)

- Requested **512 GiB zonal `pd-balanced` persistent boot disk**,
  `autoDelete=false`, in `southamerica-east1-b`; **not** 150 GiB.
  The live preflight checks size, type, boot attachment and retention.
- VM target unchanged: `e2-highmem-4` / 4 vCPU / 32 GiB RAM / CPU only.
- This is analogous to solo098's *capacity*, not its physical Lexar
  NVMe. GCE Persistent Disk is network-backed SSD storage.
- solo098's earlier layout was approximately /boot 1 GiB, swap 8 GiB,
  root/home/log Btrfs subvolumes. The current locked Nixpkgs GCE image
  imports `virtualisation/google-compute-image.nix`, which uses
  `make-disk-image.nix` with **legacy/MBR and ext4**, NOT Btrfs
  subvolumes/swap. Do not claim exact filesystem parity without a
  separate image/partition redesign and boot/recovery tests.
- `/home/klarkc` remains persistent on the root disk even while the
  machine is stopped; stop does not eliminate disk charges.
- Published Google PD-balanced illustration: US$0.000136986/GiB-hour.
  512 GiB x 730h ~= **US$51.20 per 730-hour month**; previous
  150 GiB ~= US$15.00. Difference ~= US$36.20/month for the disk
  **alone**, excluding VM, images, networking, tax, and any discounts.
  Verify the actual São Paulo SKU and billing currency before approval.
  Source: https://cloud.google.com/compute/disks-image-pricing

## What the GCE NixOS image already provides

`workstations/gcp-workstation.nix` already declares Nix/Flakes, git,
curl, wget, OpenSSH, tmux, direnv, Bash, GNU Make/GCC, Alacritty
(standard, NOT the NVIDIA/nixGL wrapper), xterm, xclip, D-Bus,
Dunst, xauth, xsetroot, xmodmap, and nix-output-monitor. Xorg and
**XMonad only** are enabled via NixOS, with `xmonad-contrib` available.
XRDP/sesman invokes the HOME XMonad wrapper when present; before
checkout it launches the NixOS XMonad with a D-Bus session. XFCE and
Lemurs are absent. CUDA/NVIDIA/vLLM remain disabled.
Google OS Login is furnished by the NixOS GCE image module.

**Not proved:** successfully compiling the user's actual
`~/.config/xmonad/xmonad.hs`, running Taffybar, logging in
interactively to XRDP with a real password, authenticating to GCP via
IAP, or executing the SoloSIG toolchain.

## Arch/yay README dependency mapping

Source: `klarkc/dotfiles/README.md`, **Arch Linux with NVidia**.
Don't run `pacman`, `yay` or Arch setup scripts on NixOS. Migrate to
declarative NixOS options and explicit Nixpkgs packages.

| Arch declarations | Migration / replacement | Priority / notes | Motivação técnica/operacional |
| --- | --- | --- | --- |
| `openssh git git-lfs wget` | OpenSSH/git/wget already; add `git-lfs` | P0 Git | Git, SSH e wget são portáveis; git-lfs é separado e necessário para repositórios com LFS. |
| `nix` | NixOS native daemon and flakes | Present | NixOS já gerencia Nix/daemon; um segundo instalador de distribuição criaria conflitos. |
| `gvim` | Nixpkgs Vim with GUI support as needed; CLI `vim` first | P1 | Vim é portável; Gvim adiciona GUI e entra apenas se houver uso real. |
| `lsd` | `pkgs.lsd` | P1: `.bashrc` aliases currently expect it | O .bashrc substitui ls por lsd; sem o binário o shell perde comandos básicos. |
| `ttf-fira-code noto-fonts-emoji` | `fonts.packages` with Fira Code / Noto emoji | P1 GUI | Fontes precisam existir no Xorg remoto para ligaturas, ícones e caracteres corretos. |
| `xmonad xmonad-contrib xorg-server` | NixOS XMonad + X server options | Base present; custom config not validated | XMonad era o desktop original; manter via módulo NixOS com xmonad-contrib, sem XFCE. |
| `lemurs` | **Omit** on server; XRDP manages remote authentication and Xorg | Replace | Lemurs gerencia login em TTY local; XRDP já autentica por PAM e cria Xorg remoto, sem console gráfico físico. Seria redundante. |
| `pipewire pipewire-audio pipewire-pulse pipewire-alsa pwvucontrol` | NixOS `services.pipewire`, WirePlumber, `pavucontrol` if RDP audio needed | P2, headless/audio unproved | Áudio local não é requisito de IAP/RDP; áudio redirecionado exige configuração XRDP e teste próprio. |
| `qt5-styleplugins` | Prefer maintained Qt theme integration; remove old `gtk2` assumptions | Replace | Plugin Qt5/GTK2 legado não tem equivalência garantida; usar integração de tema XDG/NixOS atual. |
| `dconf-editor picom feh dmenu` | Nixpkgs GUI tools, selectively | P1 desktop | São utilitários/efeitos de interface; só habilitar o que funciona em display virtual e paths restaurados. |
| `xorg-xsetroot xorg-xset xorg-xmessage xorg-xmodmap` | Nixpkgs X11 utilities; xsetroot/xmodmap already | P1 | São executáveis X11 usados por XMonad; trocar origem pacman por Nixpkgs. |
| `xclip libnotify dunst` | xclip/dunst already, add notify-send via libnotify if needed | P1 | Xclip e notificações fazem sentido em XRDP; ajustar PATH para NixOS. |
| `haskell-language-server` | Nixpkgs HLS, preferably per-project devenv | P2 Haskell | HLS deve acompanhar o GHC do projeto; evitar instalação global incompatível com devenv. |
| `taffybar libappindicator-gtk3` | Haskell Taffybar build and compatible status-notifier library; XMonad works without a panel | P1/P2; must actually compile | Taffybar usa Haskell, bateria e widget externo; manter XMonad sem painel até compilar e auditar configuração. |
| `blueman` | **Skip** (no local Bluetooth hardware) | Host-specific | VM não tem adaptador Bluetooth local; applet deve ficar na máquina física. |
| `keyd` | On Dell/client if physical keyboard remap desired, **not** GCE RDP guest | Replace/client scope | keyd remapeia teclado no kernel; o teclado real está no Dell, não no servidor RDP. |
| `the_silver_searcher` | `pkgs.silver-searcher`; ripgrep also suitable | P1 | Pesquisa de código é portável; silver-searcher mantém CLI, ripgrep é alternativa. |
| `satty scrot i3lock xss-lock` | Nixpkgs screen capture/locking; test inside XRDP session | P1 | Captura e bloqueio podem funcionar no Xorg remoto, mas precisam de teste de reconexão. |
| `sword` | Optional SWORD package after requirement confirmation | Optional | SWORD é específico e opcional; não participa do boot, acesso ou desenvolvimento SoloSIG. |
| `ffmpeg unzip htop` | Nixpkgs same/equivalent | P1 | Ferramentas CLI independem do Arch e podem vir diretamente do Nixpkgs. |
| `snapper` | Only after deliberate Btrfs layout design; current GCE image ext4 | Replace/defer | Snapper espera snapshots do filesystem; imagem GCE atual usa ext4, não Btrfs. |
| `pacreport yay-cache-cleanup-hook` | **Remove**: Nix store GC + NixOS generation retention; never delete GC roots blindly | Replace | pacman/AUR não existem em NixOS; substituir por GC do Nix preservando raízes e gerações. |
| `sunshine` | **Disable**: use IAP+XRDP, no public game-streaming ingress | Host-specific | Sunshine abriria segundo serviço de streaming e portas, desnecessários com IAP+XRDP. |
| `bat git-delta ripgrep btdu btop` | Nixpkgs `bat`, `delta`, `ripgrep`, `btdu`, `btop` | P1 | Ferramentas CLI podem ser mantidas com empacotamento declarativo Nix. |
| `handlr` | Optional Nixpkgs equivalent/desktop MIME configuration | P2 | Associações MIME podem usar XDG; não incluir gestor extra sem uso demonstrado. |
| `ollama-cuda` | **Do not migrate locally**; CPU-only VM. Use authorized remote LLM endpoint | Hard exclusion | ollama-cuda depende de GPU NVIDIA; usuário decidiu desabilitar GPU, CUDA e vLLM até nova ordem. |
| `discord enpass-bin` | Optional per-user GUI installs, not required for workstation bootstrap | P2/privacy | Discord e Enpass exigem credenciais pessoais; migração opcional após garantir sessão RDP e segredo seguro. |
| `lumen fzf mdcat` | fzf/mdcat via Nixpkgs; Lumen optional after Nix packaging check | Optional | fzf/mdcat são portáveis; Lumen depende de pacote verificado e uso confirmado. |
| `yazi` | Nixpkgs Yazi; helpers `7zip jq poppler fd fzf zoxide resvg imagemagick xclip xsel chafa` | P1 file manager | Yazi exige auxiliares para previews; migrar conjunto para não deixar funções parcialmente quebradas. |

**Extra from actual dotfiles behavior:** `git` completion, `xrandr`,
`xset`, `xss-lock`, `i3lock`, `pgrep`, `notify-send`,
`python3`, `nodejs`, `Brave/Chromium`, `Xvfb`, `xauth`
and `devenv` are referenced by scripts/config but not all supplied
by the current GCE systemPackages. A successful server-image build
does not imply these user commands work.

## Nix flake profile audit

Source: `dotfiles/flake.nix` `packages.default`, lines ~637-672
in pinned source. **Do NOT install `klarkc/dotfiles#default`** on the
CPU-only GCE image.

| Flake default package(s) | Decision | Motivação técnica/operacional |
| --- | --- | --- |
| `alacrittyWithHostGL`, `nixGLNvidia` | **Replace** with plain NixOS Alacritty (existing) or separate ligatures build; pinned NVIDIA driver and `yay` advice are invalid here | Wrapper Alacritty exige driver NVIDIA e nixGL host; usar Alacritty nativo na VM NixOS CPU-only. |
| `vllmRuntime` | **Exclude** CUDA 13 / NVIDIA; GPU not provisioned | Runtime vLLM inclui CUDA/NVIDIA; explicitamente proibido até nova ordem. |
| `nixos-rebuild`, `nix-output-monitor`, `nix-fast-build`, `flake-edit`, `uv`, `gh`, `gitleaks` | Portable Nix/CLI tools. Some already present, others need an explicit CPU-only profile | CLIs portáveis; perfil separado evita herdar dependências NVIDIA do default. |
| `direnv` | Already installed, but per-project `devenv` activation still needs verification | direnv já existe; as versões efetivas virão dos flakes/devenv dos projetos. |
| `codex`, `opencodeWithCodexAuth`, `opencodeCodexAuthTools` | **Portable with constraints**: headless OAuth/bootstrap and runtime secrets; do not copy auth blobs into the image | OpenCode/Codex podem usar modelo remoto sem GPU; OAuth deve ser restaurado em runtime, nunca na imagem. |
| `backupTools.packScript`, `backupTools.testScript` | Portable, opt-in; do not run destructive cleanup or assume backup sources are restored | Backup é portátil, mas restauração e limpeza exigem verificar dados privados antes. |
| `kolu`, `herdr` | Portable as Nix executables; verify tmux and user-session interaction. **Do not enable Kolu's `--host 0.0.0.0`** on the server before loopback binding/restricted access | Herdr/tmux são portáveis; Kolu deve escutar em loopback e não no IP externo. |
| `ledgeurRuntime` | Candidate CPU runtime; test toolchain and audio workflow separately | Runtime CPU é candidato, mas áudio/transcrição não foram verificados em servidor remoto. |
| `mcpRemoteRuntime`, `playwright-mcp` | Portable with browser/runtime dependencies and auth. Browser scripts hard-code Arch paths, see below | Ferramentas MCP portáveis; browser depende de Brave/Xvfb e caminhos /usr/bin do Arch. |
| `desktopCommanderRuntime`, `desktopCommanderMcpRuntime` | Candidate after binding to loopback/private ingress, secure auth and service review | É possível portar, mas MCP remoto exige escopo, autenticação e bind restritos. |
| `zeroclawWithLandlock` | Candidate CPU agent; default model endpoint points at local vLLM, so choose remote model or disable service. Preserve Landlock restrictions | ZeroClaw aponta para vLLM localhost desativado; manter parado até escolher provedor remoto. |

## Decisões de desktop: XMonad, XFCE e Lemurs

**XMonad fica como único desktop.** Na GCE o XRDP autentica o usuário
e inicia Xorg remotamente. Antes do checkout dos dotfiles, a sessão
usa o XMonad do NixOS com D-Bus; depois usa
`.local/bin/xmonad-session` do HOME. O módulo NixOS habilita
`xmonad-contrib` para os imports do `xmonad.hs`.

**XFCE foi removido** porque o usuário não o utilizava no solo098.
Era um desktop duplicado, com closure e serviços adicionais, sem ser
pré-requisito do XRDP. Também foi removido `xfce4-terminal`.
**Lemurs não vem** porque era o login manager do TTY local: ele não
autentica nem cria as sessões XRDP/IAP. Pode ser avaliado depois se
houver demanda por console gráfico local, mas não como requisito RDP.

A configuração XMonad traz comandos fixos de monitores físicos e
`/opt` do Arch, que devem ser adaptados antes de considerar o
desktop idêntico ao solo098. O CI não prova login XRDP autenticado.

**Migration design:** add a separately named Nix profile, preferably in
`klarkc/dotfiles` via its own reviewed change, for portable/CPU-only
tools. Do not modify that repo's main from BuildGCE. In the interim
install explicit trusted Nix packages on the **GCE NixOS server**;
never install the existing `#default` wholesale.

## Shell, GUI and runtime incompatibilities (concrete files)

| File / entry | Evidence | Required change | Motivação técnica/operacional |
| --- | --- | --- | --- |
| `.bashrc` | Unconditional `source /usr/share/git/completion/git-prompt.sh`; uses `lsd`, `direnv`, `yazi`, `sgpt`, `tmux` | Use Nix-installed Git prompt / guarded source; provide commands; avoid auto-tmux hijack of XRDP/Herdr shells | Git prompt em /usr/share é específico do Arch; proteger o source e usar localização Nix. |
| `.bashrc` + `.profile` | Imports runtime secrets from private `.profile_override`; default `LOCAL_ENDPOINT=http://localhost:11434/v1` | Restore secrets securely, never copy into Git/image; move LLM endpoint to validated remote provider when needed | .profile usa credenciais privadas e endpoint LLM local; recuperar secrets fora de Git e configurar modelo remoto. |
| `.config/xmonad/xmonad.hs` | Hard-coded `HDMI-0` / `DP-1`, `/opt/discord/Discord`, `/opt/enpass/Enpass`, physical suspend/brightness/volume, Steam | Use a separate XRDP/cloud desktop config or guard hardware-only actions by environment; never change virtual Xrandr displays from physical-monitor settings | HDMI/DP, brilho, Steam e apps em /opt são do desktop físico; XRDP usa monitor virtual. |
| `.config/taffybar/taffybar.hs` | battery and hardware widgets, network and disk widgets; additional Haskell dependencies; API credential-like literal | Compile/validate on NixOS; remove hardware-only widgets and review embedded credential-like value before enabling | Taffybar contém widgets de bateria/serviço e valor incorporado; compilar e auditar antes de ativar. |
| `.local/bin/xmonad-session` | Portable DBus session handling; requires `xset`, `xss-lock`, `i3lock`, `dunst` and actual XMonad build | Port with Nix dependencies; test real XRDP graphical login with XMonad only | Wrapper XMonad/D-Bus é reutilizável; instalar xset/locker e validar no XRDP. |
| `.local/bin/lock-screen` | Calls `i3lock` | Install and validate for XRDP, or select a safer cloud-compatible locker | i3lock trava display X; testar desbloqueio/reconexão no RDP antes de ativar. |
| `.local/bin/opencode-browser-display` | `/usr/bin/xauth`, `/usr/bin/Xvfb` | Replace with PATH-resolved or Nix store binaries | Xvfb/xauth têm paths diferentes no NixOS; referenciar pacote Nix e manter display privado. |
| `.local/bin/opencode-browser-mcp`, `...-pair` | `/usr/bin/xset`, `/usr/bin/brave`, static display `:92` | Adapt to Nix packages and ensure isolated profile is not exposed | Brave/xset absolutos em /usr/bin não são portáveis; ajustar derivação e isolamento Playwright. |
| `.local/bin/optmem-opencode-mcp`, `.config/systemd/user/optmem-*.service` | `/usr/bin/python3` hardcoded in multiple entrypoints | Replace with Nix-provided interpreter; preserve single-writer/memory isolation and private runtime paths | Python em /usr/bin é dependência do Arch; trocar por Python Nix sem quebrar single-writer OptMem. |
| `.config/systemd/user/nix-cleanup.service` | `/usr/bin/nix-collect-garbage` | Use NixOS scheduled GC / Nix store binary, never erase GC roots or old generations without review | NixOS usa GC/gerações; não apagar GC roots nem assumir localização /usr/bin. |
| `.config/systemd/user/https-proxy.service` | `/usr/lib/systemd/systemd-socket-proxyd` | Use NixOS-provided systemd tool or native socket proxy module | systemd-socket-proxyd em /usr/lib é path do Arch; usar binário NixOS. |
| `.config/opencode/opencode.json` | Current default and small model `vllm/qwen3.8-27b`; static permission root `/run/user/1000` | Select authorized GPT/remote model with no local CUDA; use actual assigned UID/runtime path; preserve MCP security | OpenCode usa vLLM ausente e UID fixo; selecionar provedor remoto e revisar sandbox. |
| `.zeroclaw/config.toml` | Default provider `http://localhost:8000/v1`, vLLM model; private bridge paths | Remote provider or explicit disabled state for CPU GCE; never assume local service exists | ZeroClaw usa servidor localhost vLLM inexistente; desabilitar até configurar remoto. |
| `.config/systemd/user/kolu.service` | `--host 0.0.0.0` | Restrict to loopback or explicit authenticated proxy before enabling | Bind 0.0.0.0 expõe serviço além de loopback; restringir antes de habilitar. |
| `.config/systemd/user/sunshine.service` | `/usr/bin/sunshine` | Do not enable: IAP/RDP supersedes gaming streamer | Sunshine não faz parte do contrato IAP/XRDP e adiciona porta/serviço extra. |
| `.local/bin/cleanup`, `pacman-*`, `.config/systemd/user/pacreport.*` | Arch `yay`, `pacman`, `pacreport`; aggressive Nix GC and deletion | Leave disabled / replace with bounded NixOS GC only | pacman/yay não existem e os scripts removem recursos agressivamente; usar GC seguro. |
| `.local/bin/home-cleanup-post` | `git stash` + `git clean -fdx` across Sources/worktrees, sudo deletion | **Never auto-enable** on cloud: destructive to uncommitted state/worktrees | git clean -fdx e sudo rm -rf podem destruir Sources/worktrees; nunca ativar automaticamente. |
| `Makefile` | Default `make` installs `#default`, runs network-fetched theme/icon scripts and npm config | Do not run whole `make`; select safe non-destructive targets | make invoca perfil NVIDIA/CUDA e scripts curl de instalação; usar alvos Nix auditados. |
| `.config/systemd/user/*.service` | Many services reference `%h/.nix-profile/bin` | Install explicit portable tools first; audit each unit and do not enable en masse | Units dependem de paths, programas e segredos do solo098; habilitar uma a uma após teste. |

## Project workloads and user state

- SoloSIG development depends on the *project's* Nix/devenv environment:
  Node/npm, Java/Maven, PostgreSQL/PostGIS/Prisma/pgkit, MapStore2,
  GeoServer/Tomcat, and other modules. These are **project-specific**
  and should be provided by its pinned flake/devenv, not copied as
  global pacman dependencies.
- Runtime requirements to validate: `nix develop`/`devenv up`,
  user namespace, filesystem permissions, native libraries, ports,
  GIS dependencies and service orchestration. PostgreSQL development
  state is **not** included merely by checking out dotfiles.
- The checkout must be **directly in `/home/klarkc/.git`** (never
  `/home/klarkc/dotfiles/.git`). The guarded bootstrap script already
  refuses conflicting HOME files; it does not restore every untracked
  file, agent session, private key, model cache or worktree from solo098.
- Private `~/.profile_override`, Enpass sync, OpenCode/Codex OAuth,
  OptMem sidecar, SSH/Git credentials, `~/Sources`, Herdr worktrees,
  historical sessions and backups have to be restored by a separate,
  verified, authenticated recovery path. Never bake them into Nix
  evaluation, CI logs, GCE metadata or machine images.
- `/home/klarkc` persistence requires an actual 512-GiB retained
  boot disk. A QEMU reboot success is not proof of GCE stop/start.
- If future GUI/agent services listen on TCP, they must not escape
  IAP-only ingress. Prefer local loopback for every dashboard/MCP.
  A green firewall test for port 3389 alone does not secure other services.

## Ordered migration and acceptance

1. **P0 / before GCE provisioning:** 512-GiB retained disk,
   least-privilege IAM+IAP, restrictive VPC/NixOS ingress,
   valid boot image, cost approval. Do not create paid resources
   implicitly. Verify real filesystem layout and root resize.
2. **P0 / first user session:** protected `/home/klarkc` direct Git
   bootstrap; safe shell Git prompt; XMonad-only cloud config and pre-HOME
   bootstrap launcher; real XRDP login through IAP; ensure no public 3389.
3. **P1 / portable developer baseline:** explicitly install shell
   essentials, fonts, editors, Yazi and helpers from Nixpkgs; create
   separate `dotfiles#cpu-gce` profile *on a dedicated dotfiles branch*
   rather than the existing NVIDIA default. Compare resolved
   executable paths and check service unit syntax.
4. **P1 / SoloSIG:** restore Sources/worktrees through verified backup;
   activate project Nix/devenv; run smoke tests per service, not
   a blanket installation of the original Arch package list.
5. **P2 / optional agents:** Codex/OpenCode OAuth, Herdr, Kolu
   loopback, OptMem, ZeroClaw remote LLM, browser MCP and desktop
   commander each get opt-in service activation and security checks.
   No CUDA/vLLM, Steam/Sunshine or Arch maintenance timers.
6. **E2E / not yet executed:** actual Dell login (or equivalent client),
   Google IAP tunnel and IAM, XRDP password login, XMonad only,
   clipboard/dynamic resolution, Nix package commands,
   stop/start reconnect, disk size/type, and persistent HOME/project
   state. **Do not close issue #21 on CI-green alone.**

## Inventory limits

Package-attribute names still need a Nixpkgs evaluation/build on the
GCE-locked flake before being marked installed. **No code in the
`klarkc/dotfiles` repo was modified.** The old Arch's installed-only
packages, live service enablement, filesystem details, and private HOME
files cannot be inferred from tracked dotfiles alone.
