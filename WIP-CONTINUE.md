# WIP continuation notes

This file is the handoff document for continuing work on the `devenv-2-migration` branch in a new conversation.

## Branch

- Working branch: `devenv-2-migration`
- Repository: `klarkc/os`
- Current HEAD at handoff: `0ab4f62f60ffdb42c4e1d7b7c8ca73a0f0ac3c48`
- HEAD commit message: `chore: pin devenv version`

## Goal

Migrate the repository from the previous flake-centric layout to a `devenv`-centric layout with these rules:

- Humans and CI use `devenv` only.
- Public UX must not require raw `nix`, `nixos-rebuild`, `nixos-install`, or direct script invocation.
- Repository organized by explicit domain under `modules/<domain>/`.
- Each domain exposes `devenv.nix`.
- `devenv.yaml` imports domain directories and relies on their `devenv.nix` entrypoints.
- `.nix` files are declarative and are only checked/evaluated.
- Executable behavior lives in `.sh` scripts.
- Every `.sh` script must have a co-localized `.test.sh`.
- Every `.test.sh` must be loaded by a `devenv.nix` module.
- Tests are run via `devenv test` only.
- CI runs `devenv` only.
- SecretSpec should be enabled globally in `devenv.yaml`.
- Avoid `default.nix`, `index.*`, and root-level category folders like `hosts/` or `tasks/`.
- Avoid unnecessary plurals in domain naming.

## Architecture correction agreed in this session

The intended deployment architecture is:

- `install-system` installs to a target.
- `update-system` runs from inside an already installed machine.

`install-system` should support at least:

- a remote machine target over SSH
- a local target such as a disk device or an image file

`update-system` should not be modeled as a remote deployment command in the final architecture.
It is an in-machine operation.

One subtle but important point: `update-system` should probably stop requiring `host` as an input. If `host` remains at all, it should be optional and used only as a guard or override, not as a remote target selector.

## Current layout

```text
modules/
  deployment/
    devenv.nix
    scripts/
      install-system.sh
      install-system.test.sh
      update-system.sh
      update-system.test.sh

  shared/
    devenv.nix
    system.nix

  ssdinarch/
    devenv.nix
    machine.nix
    instances/
      ssdinarch-0.nix
      ssdinarch-0.disko.nix

  cache/
    devenv.nix
    machine.nix
    instances/
      cache-0.nix
      cache-0.disko.nix

  recover/
    devenv.nix
    machine.nix
    instances/
      recover-0.nix
```

## Verified branch state

These items are already present on `devenv-2-migration`:

- `README.md` documents the `devenv`-only interface and the architecture correction.
- `AGENTS.md` was updated to describe the corrected install/update split.
- `.github/workflows/test.yml` exists and runs `nix run github:cachix/devenv/v2.0.6 -- test`.
- `devenv.yaml` imports the current domain modules and has a global `secretspec` block.
- `modules/deployment/devenv.nix` exists and now exposes a target-oriented install contract in progress.
- `cache-vultr` has been migrated to `cache-0`.
- `recover_0` has been migrated to `recover-0`.

## Local validation already performed

These commands were executed successfully during this session:

```bash
nix --accept-flake-config run github:cachix/devenv/v2.0.6 -- test
```

This validates that the current test suite passes through the `devenv` entrypoint.

## CI validation already performed

GitHub Actions for commit `4e9bfae973b001c8bd210e0e265b9aed88fdd9e1` was confirmed green by the user.

The user also later reported that local tests are still OK after the refactor work and that CI for the refactor commit is green too, but slow (around 30 minutes).

The important invariant to preserve is:

- CI must continue to use only `devenv`
- no extra direct `nix`/`nixos-*` command should become the public CI interface beyond `nix run github:cachix/devenv/v2.0.6 -- test` already used by the workflow bootstrap

## Cache / CI performance diagnosis from attached logs

The user attached GitHub Actions logs from a slow green run. Main findings from inspection:

- `DeterminateSystems/magic-nix-cache-action@v7` failed to restore cache with `Cache service responded with 400`.
- The same action failed to save cache with `Our services aren't available right now`.
- FlakeHub authentication/cache was disabled in that run.
- During the actual `devenv test`, the local proxy cache from magic-nix-cache was later disabled because of GitHub API rate limiting (`ResourceExhausted` / rate limit exceeded).
- After cache disablement, the job fell back to building a very large number of derivations locally, which explains the ~30 minute runtime.
- The run was green, but cache behavior was unhealthy.
- There were also warnings about ignoring untrusted flake configuration settings like `extra-substituters` and `extra-trusted-public-keys`, which may be relevant if the repository expects those to be honored during CI bootstrap.

Interpretation:

- The slow CI appears to be primarily a cache/backend problem, not a correctness failure in the repo.
- The workflow is functionally correct but operationally suboptimal.
- A likely follow-up is to simplify or harden the cache setup in `.github/workflows/test.yml` while preserving the `devenv`-only testing interface.

## What changed in this working tree (not yet committed)

### `modules/deployment/scripts/update-system.sh`

- `update-system` now runs as an in-machine flow.
- `host` is optional; it defaults to the local hostname and rejects mismatches when explicitly provided.
- Non-validate mode runs `nixos-rebuild switch` against a generated temp flake.

### `modules/deployment/scripts/install-system.sh`

- Local-target install is implemented:
  - `target_disk` runs disko to format/mount and then `nixos-install`.
  - `target_image` builds and runs `diskoImagesScript` and writes `.raw` output to `target_image`.
- `target_disk` requires a matching device in the host's disko module.
- `target_image` requires `imageSize` in the host's disko module.

### `modules/deployment/devenv.nix`

- Added `disko` to the deployment task package set.

### `modules/deployment/scripts/update-system.test.sh`

- Updated expectations for unknown host and non-root update execution.

### Docs

- `README.md` updated to describe the in-machine update flow and local-target install.
- `AGENTS.md` documents running `devenv` via `nix run`.

### CI

- `.github/workflows/test.yml` now uses `nix-community/cache-nix-action@v7` with explicit cache keys, adds minimal permissions, and runs `nix --accept-flake-config run github:cachix/devenv/v2.0.6 -- test`.

## Main remaining implementation work

### 1. Validate local-target install flows on real hardware

The local install path now exists but has not been exercised against a real disk or image target.

### 2. Confirm update-system behavior on a real installed host

`update-system` now runs `nixos-rebuild switch` locally, but it has not been run on an installed machine.

## Suggested immediate next steps for the next assistant

1. Open `WIP-CONTINUE.md` first.
2. Inspect current `README.md`, `AGENTS.md`, and `modules/deployment/*` on `devenv-2-migration`.
3. If deployment behavior changes again, update `AGENTS.md` and `README.md` in the same change.
4. Validate local-target install on a real disk/image target.
5. Validate `update-system` on a real installed host.
6. Keep GitHub Actions using only `devenv` as the testing interface.

## Explicit warnings for the next assistant

- Do not regress back to remote-update-via-SSH semantics.
- Do not claim local-target install exists until it really works.
- Do not claim operational deployment is fully verified until a real target path has been exercised.
- Preserve the `devenv`-only public interface for humans and CI.
- Keep scripts and tests co-localized under their domain.
- Keep the implementation aligned with `AGENTS.md`; if architecture changes again, update `AGENTS.md` in the same change.
