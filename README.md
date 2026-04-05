# os

[![Test](https://github.com/klarkc/os/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/klarkc/os/actions/workflows/test.yml?query=branch%3Amain)

Personal NixOS machines and operations, managed through a `devenv`-only interface.

## Principles

- Humans and CI interact with this repository through `devenv`.
- Deployment scripts are implementation details behind `devenv tasks`.
- Machine definitions live under `modules/<domain>/`.
- Instances live under `modules/<domain>/instances/<domain>-<number>.nix`.

## Intended interface

Install a host through `devenv` tasks.

The intended long-term `install-system` interface is target-oriented:

- remote machine target over SSH, or
- local target such as a disk device or an image file

The exact task inputs for the local-target flow are still being finalized.
The current implementation uses `target_disk` for direct disk installs and `target_image` for disko image generation.

`update-system` is conceptually different from install: it is intended to be run from inside an already installed machine, not as a remote deployment command.

## Current branch status

The current branch implements the split between target-oriented install and in-machine update.

Today, the documented and locally validated commands are:

```bash
devenv tasks run deployment:install-system --input host=ssdinarch-0 --input target_ssh=root@example
devenv tasks run deployment:update-system
```

This is an implementation snapshot, not the final desired interface.

The `host` input is passed to deployment tasks through `DEVENV_TASK_INPUT` and resolved by the task-backed shell scripts. For `update-system`, `host` is optional and defaults to the local hostname.

Do not treat the shell scripts under `modules/deployment/scripts/` as the public interface. The intended entrypoint is `devenv tasks`.

## Deployment behavior

Install and update generate a temporary flake from the selected instance plus `modules/shared/system.nix`.
Update runs `nixos-rebuild switch` against that temporary flake from inside the installed machine.

If `modules/<domain>/instances/<host>.disko.nix` exists, install includes the disk layout automatically and update includes that module in the generated system.
Local disk installs run disko to format/mount the target and then invoke `nixos-install` against the generated flake. Image installs build and run `diskoImagesScript` from the generated system and write the resulting `.raw` image to `target_image`.
Image installs require `imageSize` in the host's disko module.

This behavior is expected to change as the interface is brought in line with the target-oriented install flow and the in-machine update flow described above.

## Safe validation

You can validate the current task wiring without performing a real install or update:

```bash
devenv tasks run deployment:install-system --input host=ssdinarch-0 --input validate_only=true
```

```bash
devenv tasks run deployment:update-system --input validate_only=true
```

With `validate_only=true`, the current deployment scripts exit before invoking install or update operations.

## Tests

Run repository tests with:

```bash
devenv test
```

The current branch wires shell-based tests through domain `devenv.nix` modules.

## Validated locally on this branch

The following commands were executed successfully on `devenv-2-migration`:

```bash
devenv tasks list
devenv tasks run deployment:install-system --input host=ssdinarch-0 --input validate_only=true
devenv tasks run deployment:update-system --input validate_only=true
devenv test
```

This validates task discovery, safe deployment-task input handling, and local test execution for the current implementation. It does not by itself validate the final intended install/update model.

## Hosts

Currently declared hosts:

- `ssdinarch-0` in `modules/ssdinarch/instances/`
- `cache-0` in `modules/cache/instances/`
- `recover-0` in `modules/recover/instances/`

## Secrets

`devenv.yaml` enables SecretSpec globally for the repository.

Secret material is provided out of band by the operator. Enpass is the current operator-side source of truth, and secrets are expected to be injected locally rather than committed.

The cache host expects a Nix cache signing key at `/etc/nixos/secrets/cache.key`.
