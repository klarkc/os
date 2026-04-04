# os

[![Test](https://github.com/klarkc/os/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/klarkc/os/actions/workflows/test.yml?query=branch%3Amain)

Personal NixOS machines and operations, managed through a `devenv`-only interface.

## Principles

- Humans and CI interact with this repository through `devenv`.
- Deployment scripts are implementation details behind `devenv tasks`.
- Machine definitions live under `modules/<domain>/`.
- Instances live under `modules/<domain>/instances/<domain>-<number>.nix`.

## Interface

Install a host:

```bash
devenv tasks run deployment:install-system --input host=ssdinarch-0
```

Update a host:

```bash
devenv tasks run deployment:update-system --input host=ssdinarch-0
```

The `host` input is passed to deployment tasks through `DEVENV_TASK_INPUT` and resolved by the task-backed shell scripts.

Do not treat the shell scripts under `modules/deployment/scripts/` as the public interface. The intended entrypoint is `devenv tasks`.

## Deployment behavior

Install and update generate a temporary flake from the selected instance plus `modules/shared/system.nix`.

If `modules/<domain>/instances/<host>.disko.nix` exists, install includes the disk layout automatically and update mounts through `nixos-anywhere` before switching.

Target SSH defaults to `root@<host>:22`. Override with:

```bash
DEPLOY_TARGET_USER=root DEPLOY_TARGET_HOST=ssdinarch-0 DEPLOY_TARGET_PORT=22 \
  devenv tasks run deployment:install-system --input host=ssdinarch-0
```

Use the same `DEPLOY_TARGET_*` environment variables for update.

## Tests

Run repository tests with:

```bash
devenv test
```

The current branch wires shell-based tests through domain `devenv.nix` modules.

## Hosts

Currently declared hosts:

- `ssdinarch-0` in `modules/ssdinarch/instances/`
- `cache-0` in `modules/cache/instances/`
- `recover-0` in `modules/recover/instances/`

## Secrets

`devenv.yaml` enables SecretSpec globally for the repository.

Secret material is provided out of band by the operator. Enpass is the current operator-side source of truth, and secrets are expected to be injected locally rather than committed.

The cache host expects a Nix cache signing key at `/etc/nixos/secrets/cache.key`.
