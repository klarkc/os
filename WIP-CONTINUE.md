# WIP continuation notes

This file is the handoff document for continuing work on the `devenv-2-migration` branch in a new conversation.

## Branch

- Working branch: `devenv-2-migration`
- Repository: `klarkc/os`

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

## Verified current state on the branch

These items are already present on `devenv-2-migration`:

- `README.md` exists and documents the `devenv`-only interface.
- `.github/workflows/test.yml` exists and runs `nix run github:cachix/devenv -- test`.
- `devenv.yaml` imports the current domain modules and has a global `secretspec` block.
- `modules/deployment/devenv.nix` wires deployment tasks to scripts under `modules/deployment/scripts/`.
- `cache-vultr` has been migrated to `cache-0`.
- `recover_0` has been migrated to `recover-0`.

## Secrets

User decided that:

- No `modules/secret/devenv.nix` is needed.
- No `modules/<host>/secret.nix` is needed by default.
- SecretSpec should be enabled by a global option in `devenv.yaml`.
- Enpass is the operator's secret source.
- README should explain how SecretSpec is enabled and how local secret injection is expected to work.

The exact SecretSpec configuration syntax should still be verified against current devenv docs before calling the migration fully finished.

## What was already created or updated on the branch

- `AGENTS.md`
- `COMMIT_GUIDELINES.md`
- `README.md`
- `WIP-CONTINUE.md`
- `devenv.yaml`
- `.github/workflows/test.yml`
- `modules/deployment/devenv.nix`
- `modules/deployment/scripts/install-system.sh`
- `modules/deployment/scripts/install-system.test.sh`
- `modules/deployment/scripts/update-system.sh`
- `modules/deployment/scripts/update-system.test.sh`
- `modules/shared/devenv.nix`
- `modules/shared/system.nix`
- `modules/ssdinarch/devenv.nix`
- `modules/ssdinarch/machine.nix`
- `modules/ssdinarch/instances/ssdinarch-0.nix`
- `modules/ssdinarch/instances/ssdinarch-0.disko.nix`
- `modules/cache/devenv.nix`
- `modules/cache/machine.nix`
- `modules/cache/instances/cache-0.nix`
- `modules/cache/instances/cache-0.disko.nix`
- `modules/recover/devenv.nix`
- `modules/recover/machine.nix`
- `modules/recover/instances/recover-0.nix`

## Open items that still need verification

### 1. Verify current devenv conventions

Still worth validating against current devenv docs or local execution:

- whether the `secretspec` block in `devenv.yaml` matches current expected syntax
- whether the current task/input shape in `modules/deployment/devenv.nix` is the preferred contemporary syntax
- whether `enterTest` is the intended long-term test aggregation mechanism here

### 2. Validate deployment flows end-to-end

`install-system.sh` and `update-system.sh` should be treated as implemented but not yet fully verified end-to-end.

They already:

- validate the host argument robustly
- use the repository layout under `modules/<domain>/instances/`
- stay behind `devenv` tasks as the intended interface

What remains is confirming they behave correctly under real `devenv` execution for the declared hosts.

### 3. Tighten docs wording

The main docs task left is alignment, not creation.

Recommended focus:

- keep `README.md` tightly aligned with the current branch behavior
- keep `AGENTS.md` focused on rules that are actually reflected in the repo
- avoid describing README or CI as missing, because they already exist on this branch

### 4. CI status is still unknown

CI configuration exists, but passing status has not been verified from this handoff alone.
Do not claim CI is passing until the branch is actually checked.

## Practical next steps in a new conversation

1. Open `WIP-CONTINUE.md` first.
2. Inspect `README.md`, `AGENTS.md`, `devenv.yaml`, and `modules/deployment/devenv.nix`.
3. Verify current devenv docs or local execution for task syntax, test integration, and SecretSpec syntax.
4. Run or ask the user to run the smallest useful local validation commands.
5. Only then claim the migration is fully verified.

## Explicit warnings for the next assistant

- Prefer updating the existing docs over creating parallel replacements.
- Distinguish clearly between implemented state and verified state.
- Keep the user-visible interface restricted to `devenv`.
- Do not claim CI is passing without evidence.
