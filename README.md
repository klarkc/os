# os

[![Test](https://github.com/klarkc/os/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/klarkc/os/actions/workflows/test.yml?query=branch%3Amain)

Personal NixOS machines and operations, managed via `devenv`.

## Interface

All human and CI interaction goes through `devenv`.

## Tasks

Install a host (optionally runs `disko` if `modules/<domain>/instances/<host>.disko.nix` exists):

```bash
devenv tasks run deployment:install-system --input host=ssdinarch-0
```

Update a host:

```bash
devenv tasks run deployment:update-system --input host=ssdinarch-0
```

Run repository tests:

```bash
devenv test
```

## Hosts

- `ssdinarch-0`
- `cache-vultr`
- `recover-0`

## Secrets

SecretSpec is enabled globally via `devenv.yaml`. Secret material is provided out of band (Enpass for the operator) and should be injected locally. No real secrets are committed to the repo.

The cache host expects a Nix cache signing key at `/etc/nixos/secrets/cache.key`.
