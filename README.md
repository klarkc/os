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
