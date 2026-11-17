# os

[![Test](https://github.com/klarkc/os/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/klarkc/os/actions/workflows/test.yml?query=branch%3Amain)

Personal collection of NixOS machines.

## Deploying

### Cache

```bash
nixos-rebuild switch --flake .#cache-vultr --target-host "root@cache.tcp4.me"
```

## Migration inventory (archived user configuration)

The archived user configuration repository is **historical reference only**.
Migrate reviewed pieces into shared Nix modules inside this repository. Extend
the common modules for GCE, Dell thin client and a future ARM system; do not
duplicate packages, profiles or services.

| Priority | Components to recover | Policy |
| --- | --- | --- |
| P0 | Git privacy checks, Gitleaks, staged-content audits, safe history guards | Generic redacted tests and hooks, no private IDs |
| P0 | XMonad, D-Bus session, terminal, shell, fonts, themes, Brave/Enpass | Nix-managed user configuration with XRDP-specific overrides |
| P1 | Vim, tmux, direnv, developer CLI, Git settings | Shared portable developer profile |
| P1 | OpenCode, browser integrations, MCP and session utilities | Optional services; loopback and private runtime credentials |
| P1 | Backup/restore tools and integrity checks | Nix packages and repeatable shell tests |
| P2 | Notification daemon, maintenance, local search and memory integrations | Opt-in services; no automatic migration of personal data |
| Future ARM | GPU-backed model-serving techniques | Only after the actual hardware stack is proven |

Do not migrate legacy installation Makefiles, Arch/AUR/NVIDIA wrappers,
private files, vaults, OAuth tokens or archived histories. Where the
allowlist excludes legacy file formats, design a Nix/Shell equivalent and
keep tests before removing the old input.

## Source policy

The only maintained GitHub Actions workflows are `test.yml` and
`deployment.yml`. Dependency updates use Dependabot for Nix and Actions,
with reviewed temporary bot PRs targeting `main`. No changelog,
release-please, new releases or new Git tags.

The format gate script in `workstations/tests/repository-file-policy.sh`
runs in both CI (strict) and local hooks (advisory). Existing violations
must be migrated without breaking reproducibility or private state.

---

## Determinate Nix and weekly GC on wsklarkc

Official NixOS module pinned to Determinate v3.24.1 in `flake.lock`,
imported only for the GCE workstation and its QEMU tests.

### Exactly one automatic garbage collector

Determinate Nixd's automatic collector is disabled through
`/etc/determinate/config.json` (`garbageCollector.strategy=disabled`).
NixOS owns the weekly `nix-gc.timer` (Sunday 03:35 America/Bahia, 30m
random delay and persistent catch-up).
`nix-collect-garbage --delete-older-than 30d` prunes old generations
while preserving currently referenced system/user profiles and store
roots. The service runs with low CPU and I/O scheduling priority.

Protect important custom build outputs with a durable Nix GC root.
Never remove active roots or profiles to free disk, or treat GC as a backup.

Read-only checks after boot:
```sh
systemctl list-timers nix-gc.timer
systemctl cat nix-daemon.service
cat /etc/determinate/config.json
journalctl -u nix-gc.service --since '30 days ago'
nix-store --gc --print-roots
nix-store --gc --print-dead
df -h /nix
```

CI evaluates the GC policy and checks the daemon/timer in QEMU.
A real disk-pressure test is still pending an explicitly approved
disposable VM. It must preserve live roots, running jobs and user data.
Do not activate paid GCE deploy or automatic suspend without approval.

Official instructions: https://docs.determinate.systems/guides/advanced-installation/
GC configuration: https://docs.determinate.systems/determinate-nix/determinate-nixd/
