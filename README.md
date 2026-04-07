# os

[![Test](https://github.com/klarkc/os/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/klarkc/os/actions/workflows/test.yml?query=branch%3Amain)

Personal NixOS machines and operations, managed through a `devenv`-only interface.

## Setup

Install the pinned `devenv` CLI once with:

```bash
nix profile add github:cachix/devenv/v2.0.6
```

After that, use `devenv` directly for the repository interface shown below.

## Principles

- Humans and CI interact with this repository through `devenv`.
- Deployment scripts are implementation details behind `devenv tasks`.
- Machine domains live under `modules/<domain>/`.
- `devenv` `machines.<name>` entries should use the concrete machine name directly, such as `cache-0`.

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
Internally, the deployment commands are exposed through packaged bash applications in `modules/deployment/devenv.nix`.

## Deployment behavior

Install and update are being migrated away from temporary generated flakes and toward checked-in machine evaluators plus `devenv` machine outputs.
Update uses a built system store path from the selected machine and runs `nixos-rebuild switch --store-path` on the installed machine.

If the selected machine includes a disk layout module, install includes that automatically.
Local disk installs run disko to format and mount the target and then invoke `nixos-install` with the built system path.
Image installs build and run `diskoImagesScript` from the selected machine and write the resulting `.raw` image to `target_image`.
Image installs still require `imageSize` in the machine's disk layout module.

For internal or packaged command use, `install-system` and `update-system` also accept `--repo-root <path>`.
If `--repo-root` is omitted, they warn and assume the current working directory is the repository root.

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

- `ssdinarch-0` in `modules/ssdinarch/ssdinarch-0.nix`
- `cache-0` in `modules/cache/cache-0.nix`
- `recover-0` in `modules/recover/recover-0.nix`

## Secrets

`devenv.yaml` enables SecretSpec globally for the repository.

Secret material is provided out of band by the operator. Enpass is the current operator-side source of truth, and secrets are expected to be injected locally rather than committed.

The cache host expects a Nix cache signing key at `/etc/nixos/secrets/cache.key`.
