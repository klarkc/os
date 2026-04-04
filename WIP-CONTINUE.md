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

## Validation performed locally

The following commands were executed successfully on this branch:

```bash
devenv tasks list
devenv tasks run deployment:install-system --input host=ssdinarch-0 --input validate_only=true
devenv tasks run deployment:update-system --input host=ssdinarch-0 --input validate_only=true
devenv test
```

These results confirm that:

- deployment tasks are discovered correctly
- `host` input is accepted by the deployment tasks
- `validate_only=true` prevents real install/update execution
- local `devenv test` execution completes successfully

These results do **not** yet prove that a real install/update against a target machine succeeds.

## Secrets

User decided that:

- No `modules/secret/devenv.nix` is needed.
- No `modules/<host>/secret.nix` is needed by default.
- SecretSpec should be enabled by a global option in `devenv.yaml`.
- Enpass is the operator's secret source.
- README should explain how SecretSpec is enabled and how local secret injection is expected to work.

The exact SecretSpec configuration syntax may still be worth checking against current devenv docs, but it no longer blocks basic local validation of this branch.

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

### 1. Real deployment against a target host

What remains unverified is a real install or update against an actual machine.
Until that happens, do not claim operational deployment has been validated end-to-end.

### 2. CI status on GitHub Actions

CI configuration exists, but GitHub Actions status still has not been confirmed from this handoff alone.
Do not claim CI is passing until the branch is actually checked on GitHub.

### 3. Optional refinement of devenv conventions

Still worth validating against current devenv docs if desired:

- whether the `secretspec` block in `devenv.yaml` matches current expected syntax
- whether the current task/input shape in `modules/deployment/devenv.nix` is the preferred contemporary syntax
- whether `enterTest` is the intended long-term test aggregation mechanism here

These are refinement questions now, not blockers for the validated local workflow above.

## Practical next steps in a new conversation

1. Open `WIP-CONTINUE.md` first.
2. Inspect `README.md`, `AGENTS.md`, `devenv.yaml`, and `modules/deployment/devenv.nix`.
3. Distinguish clearly between local validation already completed and operational validation still pending.
4. Only claim the migration is fully verified after real target-host deployment and CI confirmation.

## Explicit warnings for the next assistant

- Prefer updating the existing docs over creating parallel replacements.
- Distinguish clearly between implemented state, locally validated state, and fully operationally verified state.
- Keep the user-visible interface restricted to `devenv`.
- Do not claim CI is passing without evidence.
