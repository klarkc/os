# WIP continuation notes

This file is the handoff document for continuing work on the `devenv-2-migration` branch in a new conversation.

## Branch

- Working branch: `devenv-2-migration`
- Repository: `klarkc/os`
- Current HEAD at handoff: `e85d229b655539f8ac583f06f26c286fb93be3f5`
- HEAD commit message: `refactor(deployment): separate target install from in-machine update`

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
- `.github/workflows/test.yml` exists and runs `nix run github:cachix/devenv -- test`.
- `devenv.yaml` imports the current domain modules and has a global `secretspec` block.
- `modules/deployment/devenv.nix` exists and now exposes a target-oriented install contract in progress.
- `cache-vultr` has been migrated to `cache-0`.
- `recover_0` has been migrated to `recover-0`.

## Local validation already performed

These commands were executed successfully during this session:

```bash
devenv tasks list
devenv tasks run deployment:install-system --input host=ssdinarch-0 --input validate_only=true
devenv tasks run deployment:update-system --input host=ssdinarch-0 --input validate_only=true
devenv test
```

This validates that:

- the current tasks load correctly
- `validate_only=true` works as a safety rail for both scripts
- local `devenv test` passes on the branch

## CI validation already performed

GitHub Actions for commit `4e9bfae973b001c8bd210e0e265b9aed88fdd9e1` was confirmed green by the user.

The user also later reported that local tests are still OK after the refactor work and that CI for the refactor commit is green too, but slow (around 30 minutes).

The important invariant to preserve is:

- CI must continue to use only `devenv`
- no extra direct `nix`/`nixos-*` command should become the public CI interface beyond `nix run github:cachix/devenv -- test` already used by the workflow bootstrap

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

## What changed in the latest implementation commit

Commit `e85d229b655539f8ac583f06f26c286fb93be3f5` made an intentional intermediate refactor.

### `modules/deployment/devenv.nix`

- `deployment:install-system` inputs now include:
  - `host`
  - `target_ssh`
  - `target_port`
  - `target_disk`
  - `target_image`
  - `validate_only`
- `deployment:update-system` still includes:
  - `host`
  - `validate_only`

### `modules/deployment/scripts/install-system.sh`

- still resolves the host and shared/instance modules
- now enforces that only one target kind may be chosen
- still supports the SSH-oriented path
- explicitly rejects `target_disk` and `target_image` at runtime with a clear message because local-target install is not implemented yet

### `modules/deployment/scripts/update-system.sh`

- no longer pretends to do remote update via `nixos-anywhere`
- in non-`validate_only` mode it now fails intentionally with a message that update must run inside the installed machine and is still pending

### tests

- install test now checks conflicting target kinds
- update test now checks that non-validate execution fails intentionally until the in-machine implementation exists

This commit is useful because it stops pretending that the old remote-update architecture is acceptable. It is an honest intermediate state, not the final implementation.

## Main remaining implementation work

### 1. Fix `update-system` interface and implementation

This is the most obviously incomplete area.

Desired direction:

- remove `host` as a required input to `deployment:update-system`
- make `update-system` operate as an in-machine flow
- decide how the script discovers the correct instance/config locally
- optionally allow a non-required `host` only as a sanity check

The current script intentionally exits with `implementation pending` outside validate-only mode.

### 2. Implement local-target install for `install-system`

Desired direction:

- support install to `target_disk`
- optionally support install to `target_image`
- preserve SSH install as one target mode, not the only mode
- keep the one-target-kind-only validation

The current script explicitly says local install targets are part of the intended interface but not implemented yet.

### 3. Decide how local update should locate its system definition

This needs an explicit design choice.
Possible directions:

- derive instance from current hostname
- derive instance from a marker file stored at install time
- accept an optional override argument for exceptional cases

Do not continue with a model where `update-system` behaves like a remote deployment command.

### 4. Revisit CI cache strategy

The workflow is green but slow.

Potential next steps:

- inspect `.github/workflows/test.yml`
- decide whether to keep `magic-nix-cache-action`
- consider disabling FlakeHub integration if unused
- investigate whether the workflow should explicitly trust or avoid flake-provided substituter settings
- preserve the rule that tests are still invoked through `devenv` only

## Suggested immediate next steps for the next assistant

1. Open `WIP-CONTINUE.md` first.
2. Inspect current `README.md`, `AGENTS.md`, and `modules/deployment/*` on `devenv-2-migration`.
3. Treat `e85d229b655539f8ac583f06f26c286fb93be3f5` as the starting point.
4. First complete `update-system` as an in-machine flow.
5. Then implement `install-system` for `target_disk` and optionally `target_image`.
6. Run local `devenv test` after each step.
7. Keep GitHub Actions using only `devenv` as the testing interface.
8. If changing the cache strategy, keep that change separate from deployment-logic changes if possible.

## Explicit warnings for the next assistant

- Do not regress back to remote-update-via-SSH semantics.
- Do not claim local-target install exists until it really works.
- Do not claim operational deployment is fully verified until a real target path has been exercised.
- Preserve the `devenv`-only public interface for humans and CI.
- Keep scripts and tests co-localized under their domain.
- Keep the implementation aligned with `AGENTS.md`; if architecture changes again, update `AGENTS.md` in the same change.
