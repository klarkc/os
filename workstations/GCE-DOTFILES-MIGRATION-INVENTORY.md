# Inventory: solo098 Arch Linux dotfiles to CPU-only NixOS GCE

**Evidence date:** 2026-10-27. Source snapshot: [klarkc/dotfiles main at
`0f2dbfda51d57a0539317a1ef7c1ff084c5513db`](https://github.com/klarkc/dotfiles/tree/0f2dbfda51d57a0539317a1ef7c1ff084c5513db).
Target: [BuildGCE branch](https://github.com/klarkc/os/tree/feat/solo-gce-workstation-20261026),
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
(standard, NOT the NVIDIA/nixGL wrapper), xfce4-terminal, xclip, D-Bus,
Dunst, xauth, xsetroot, xmodmap, and nix-output-monitor. Xorg,
XFCE and XMonad are enabled via NixOS; XRDP/sesman is configured,
with a conditional HOME XMonad wrapper and XFCE fallback. Google
OS Login is furnished by the NixOS GCE image module.

**Not proved:** successfully compiling the user's actual
`~/.config/xmonad/xmonad.hs`, running Taffybar, logging in
interactively to XRDP with a real password, authenticating to GCP via
IAP, or executing the SoloSIG toolchain.

## Arch/yay README dependency mapping

Source: `klarkc/dotfiles/README.md`, **Arch Linux with NVidia**.
Don't run `pacman`, `yay` or Arch setup scripts on NixOS. Migrate to
declarative NixOS options and explicit Nixpkgs packages.

| Arch declarations | Migration / replacement | Priority / notes |
| --- | --- | --- |
| `openssh git git-lfs wget` | OpenSSH/git/wget already; add `git-lfs` | P0 Git |
| `nix` | NixOS native daemon and flakes | Present |
| `gvim` | Nixpkgs Vim with GUI support as needed; CLI `vim` first | P1 |
| `lsd` | `pkgs.lsd` | P1: `.bashrc` aliases currently expect it |
| `ttf-fira-code noto-fonts-emoji` | `fonts.packages` with Fira Code / Noto emoji | P1 GUI |
| `xmonad xmonad-contrib xorg-server` | NixOS XMonad + X server options | Base present; custom config not validated |
| `lemurs` | **Do not install** on server; XRDP/session manager replaces local login | Replace |
| `pipewire pipewire-audio pipewire-pulse pipewire-alsa pwvucontrol` | NixOS `services.pipewire`, WirePlumber, `pavucontrol` if RDP audio needed | P2, headless/audio unproved |
| `qt5-styleplugins` | Prefer maintained Qt theme integration; remove old `gtk2` assumptions | Replace |
| `dconf-editor picom feh dmenu` | Nixpkgs GUI tools, selectively | P1 desktop |
| `xorg-xsetroot xorg-xset xorg-xmessage xorg-xmodmap` | Nixpkgs X11 utilities; xsetroot/xmodmap already | P1 |
| `xclip libnotify dunst` | xclip/dunst already, add notify-send via libnotify if needed | P1 |
| `haskell-language-server` | Nixpkgs HLS, preferably per-project devenv | P2 Haskell |
| `taffybar libappindicator-gtk3` | Haskell Taffybar build and compatible status-notifier library; alternatively XFCE panel | P1/P2; must actually compile |
| `blueman` | **Skip** (no local Bluetooth hardware) | Host-specific |
| `keyd` | On Dell/client if physical keyboard remap desired, **not** GCE RDP guest | Replace/client scope |
| `the_silver_searcher` | `pkgs.silver-searcher`; ripgrep also suitable | P1 |
| `satty scrot i3lock xss-lock` | Nixpkgs screen capture/locking; test inside XRDP session | P1 |
| `sword` | Optional SWORD package after requirement confirmation | Optional |
| `ffmpeg unzip htop` | Nixpkgs same/equivalent | P1 |
| `snapper` | Only after deliberate Btrfs layout design; current GCE image ext4 | Replace/defer |
| `pacreport yay-cache-cleanup-hook` | **Remove**: Nix store GC + NixOS generation retention; never delete GC roots blindly | Replace |
| `sunshine` | **Disable**: use IAP+XRDP, no public game-streaming ingress | Host-specific |
| `bat git-delta ripgrep btdu btop` | Nixpkgs `bat`, `delta`, `ripgrep`, `btdu`, `btop` | P1 |
| `handlr` | Optional Nixpkgs equivalent/desktop MIME configuration | P2 |
| `ollama-cuda` | **Do not migrate locally**; CPU-only VM. Use authorized remote LLM endpoint | Hard exclusion |
| `discord enpass-bin` | Optional per-user GUI installs, not required for workstation bootstrap | P2/privacy |
| `lumen fzf mdcat` | fzf/mdcat via Nixpkgs; Lumen optional after Nix packaging check | Optional |
| `yazi` | Nixpkgs Yazi; helpers `7zip jq poppler fd fzf zoxide resvg imagemagick xclip xsel chafa` | P1 file manager |

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

| Flake default package(s) | Decision |
| --- | --- |
| `alacrittyWithHostGL`, `nixGLNvidia` | **Replace** with plain NixOS Alacritty (existing) or separate ligatures build; pinned NVIDIA driver and `yay` advice are invalid here |
| `vllmRuntime` | **Exclude** CUDA 13 / NVIDIA; GPU not provisioned |
| `nixos-rebuild`, `nix-output-monitor`, `nix-fast-build`, `flake-edit`, `uv`, `gh`, `gitleaks` | Portable Nix/CLI tools. Some already present, others need an explicit CPU-only profile |
| `direnv` | Already installed, but per-project `devenv` activation still needs verification |
| `codex`, `opencodeWithCodexAuth`, `opencodeCodexAuthTools` | **Portable with constraints**: headless OAuth/bootstrap and runtime secrets; do not copy auth blobs into the image |
| `backupTools.packScript`, `backupTools.testScript` | Portable, opt-in; do not run destructive cleanup or assume backup sources are restored |
| `kolu`, `herdr` | Portable as Nix executables; verify tmux and user-session interaction. **Do not enable Kolu's `--host 0.0.0.0`** on the server before loopback binding/restricted access |
| `ledgeurRuntime` | Candidate CPU runtime; test toolchain and audio workflow separately |
| `mcpRemoteRuntime`, `playwright-mcp` | Portable with browser/runtime dependencies and auth. Browser scripts hard-code Arch paths, see below |
| `desktopCommanderRuntime`, `desktopCommanderMcpRuntime` | Candidate after binding to loopback/private ingress, secure auth and service review |
| `zeroclawWithLandlock` | Candidate CPU agent; default model endpoint points at local vLLM, so choose remote model or disable service. Preserve Landlock restrictions |

**Migration design:** add a separately named Nix profile, preferably in
`klarkc/dotfiles` via its own reviewed change, for portable/CPU-only
tools. Do not modify that repo's main from BuildGCE. In the interim
install explicit trusted Nix packages on the **GCE NixOS server**;
never install the existing `#default` wholesale.

## Shell, GUI and runtime incompatibilities (concrete files)

| File / entry | Evidence | Required change |
| --- | --- | --- |
| `.bashrc` | Unconditional `source /usr/share/git/completion/git-prompt.sh`; uses `lsd`, `direnv`, `yazi`, `sgpt`, `tmux` | Use Nix-installed Git prompt / guarded source; provide commands; avoid auto-tmux hijack of XRDP/Herdr shells |
| `.bashrc` + `.profile` | Imports runtime secrets from private `.profile_override`; default `LOCAL_ENDPOINT=http://localhost:11434/v1` | Restore secrets securely, never copy into Git/image; move LLM endpoint to validated remote provider when needed |
| `.config/xmonad/xmonad.hs` | Hard-coded `HDMI-0` / `DP-1`, `/opt/discord/Discord`, `/opt/enpass/Enpass`, physical suspend/brightness/volume, Steam | Use a separate XRDP/cloud desktop config or guard hardware-only actions by environment; never change virtual Xrandr displays from physical-monitor settings |
| `.config/taffybar/taffybar.hs` | battery and hardware widgets, network and disk widgets; additional Haskell dependencies; API credential-like literal | Compile/validate on NixOS; remove hardware-only widgets and review embedded credential-like value before enabling |
| `.local/bin/xmonad-session` | Portable DBus session handling; requires `xset`, `xss-lock`, `i3lock`, `dunst` and actual XMonad build | Port with Nix dependencies; test real XRDP graphical login; XFCE remains safe fallback |
| `.local/bin/lock-screen` | Calls `i3lock` | Install and validate for XRDP, or select a safer cloud-compatible locker |
| `.local/bin/opencode-browser-display` | `/usr/bin/xauth`, `/usr/bin/Xvfb` | Replace with PATH-resolved or Nix store binaries |
| `.local/bin/opencode-browser-mcp`, `...-pair` | `/usr/bin/xset`, `/usr/bin/brave`, static display `:92` | Adapt to Nix packages and ensure isolated profile is not exposed |
| `.local/bin/optmem-opencode-mcp`, `.config/systemd/user/optmem-*.service` | `/usr/bin/python3` hardcoded in multiple entrypoints | Replace with Nix-provided interpreter; preserve single-writer/memory isolation and private runtime paths |
| `.config/systemd/user/nix-cleanup.service` | `/usr/bin/nix-collect-garbage` | Use NixOS scheduled GC / Nix store binary, never erase GC roots or old generations without review |
| `.config/systemd/user/https-proxy.service` | `/usr/lib/systemd/systemd-socket-proxyd` | Use NixOS-provided systemd tool or native socket proxy module |
| `.config/opencode/opencode.json` | Current default and small model `vllm/qwen3.8-27b`; static permission root `/run/user/1000` | Select authorized GPT/remote model with no local CUDA; use actual assigned UID/runtime path; preserve MCP security |
| `.zeroclaw/config.toml` | Default provider `http://localhost:8000/v1`, vLLM model; private bridge paths | Remote provider or explicit disabled state for CPU GCE; never assume local service exists |
| `.config/systemd/user/kolu.service` | `--host 0.0.0.0` | Restrict to loopback or explicit authenticated proxy before enabling |
| `.config/systemd/user/sunshine.service` | `/usr/bin/sunshine` | Do not enable: IAP/RDP supersedes gaming streamer |
| `.local/bin/cleanup`, `pacman-*`, `.config/systemd/user/pacreport.*` | Arch `yay`, `pacman`, `pacreport`; aggressive Nix GC and deletion | Leave disabled / replace with bounded NixOS GC only |
| `.local/bin/home-cleanup-post` | `git stash` + `git clean -fdx` across Sources/worktrees, sudo deletion | **Never auto-enable** on cloud: destructive to uncommitted state/worktrees |
| `Makefile` | Default `make` installs `#default`, runs network-fetched theme/icon scripts and npm config | Do not run whole `make`; select safe non-destructive targets |
| `.config/systemd/user/*.service` | Many services reference `%h/.nix-profile/bin` | Install explicit portable tools first; audit each unit and do not enable en masse |

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
   bootstrap; safe shell Git prompt; XMonad cloud config or XFCE
   fallback; real XRDP login through IAP; ensure no public 3389.
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
   Google IAP tunnel and IAM, XRDP password login, XMonad or XFCE,
   clipboard/dynamic resolution, Nix package commands,
   stop/start reconnect, disk size/type, and persistent HOME/project
   state. **Do not close issue #21 on CI-green alone.**

## Inventory limits

Package-attribute names still need a Nixpkgs evaluation/build on the
GCE-locked flake before being marked installed. **No code in the
`klarkc/dotfiles` repo was modified.** The old Arch's installed-only
packages, live service enablement, filesystem details, and private HOME
files cannot be inferred from tracked dotfiles alone.
