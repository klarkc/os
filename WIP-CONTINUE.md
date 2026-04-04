# WIP continuation notes

This file is the handoff document for continuing work on the `devenv-2-migration` branch in a new conversation.

## Branch

- Working branch: `devenv-2-migration`
- Repository: `klarkc/os`

## Goal

Migrate the repository from the current flake-centric layout to a `devenv`-centric layout with these rules:

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

## Important correction from the user

Tasks should use script paths from their domain `devenv.nix` as documented in `AGENTS.md`. The implementation drifted and needs correction.

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

## Secrets

User decided that:

- No `modules/secret/devenv.nix` is needed.
- No `modules/<host>/secret.nix` is needed by default.
- SecretSpec should be enabled by a global option in `devenv.yaml`.
- Enpass is the operator's secret source.
- README must explain how SecretSpec is enabled and how local secret injection is expected to work.

The exact SecretSpec configuration syntax must be verified against current devenv docs before finalizing.

## What was already created on the branch

These files were created or updated during the session:

- `AGENTS.md`
- `devenv.yaml`
- `modules/deployment/devenv.nix`
- `modules/deployment/scripts/install-system.sh`
- `modules/deployment/scripts/install-system.test.sh`
- `modules/deployment/scripts/update-system.sh`
- `modules/deployment/scripts/update-system.test.sh`
- `modules/ssdinarch/devenv.nix`
- `modules/ssdinarch/machine.nix`
- `modules/shared/devenv.nix`
- `modules/shared/system.nix`
- `modules/cache/devenv.nix`
- `modules/cache/machine.nix`
- `modules/cache/instances/cache-0.nix`
- `modules/cache/instances/cache-0.disko.nix`
- `modules/recover/devenv.nix`
- `modules/recover/machine.nix`
- `modules/recover/instances/recover-0.nix`

These files were only partially aligned with the final conventions and likely need edits.

## Problems to fix

### 1. AGENTS.md must be reviewed and updated

The current `AGENTS.md` was written before the final refinements. It must be updated to reflect all final rules, especially:

- tasks must call scripts from `scripts/`
- every `.test.sh` is loaded by a `devenv.nix`
- `.nix` files are not tested directly
- SecretSpec is enabled globally in `devenv.yaml`
- domains live under `modules/<domain>/`
- humans and CI use `devenv` only
- avoid `default.nix`, `index.*`, root-level category folders, and unnecessary plurals

### 2. `devenv.yaml` likely needs edits

Expected direction:

- import `./modules/deployment`
- import `./modules/shared`
- import `./modules/ssdinarch`
- import `./modules/cache`
- import `./modules/recover`
- enable SecretSpec globally using the correct contemporary syntax

Current syntax may be incorrect and should be verified against current devenv docs.

### 3. Task modules need correction

`modules/deployment/devenv.nix` needs to be checked against real devenv task syntax.

Specific issue discovered during the session:

- argument passing was mishandled
- tasks must call their scripts properly
- tests should not be wired via ad-hoc misuse of `enterTest` if devenv has a more appropriate test registration mechanism

If `devenv test` relies on `enterTest`, then centralize that behavior cleanly in the `test` domain. Otherwise use the recommended contemporary mechanism.

### 4. install/update scripts need hardening

`install-system.sh` and `update-system.sh` should:

- validate host argument robustly
- use only the repository layout under `modules/<domain>/instances/`
- remain callable only through devenv tasks as the official UX

### 5. `ssdinarch` host is incomplete

Need to ensure the new minimal host exists and is coherent.

Expected direction:

- `modules/ssdinarch/devenv.nix`
- `modules/ssdinarch/machine.nix`
- `modules/ssdinarch/instances/ssdinarch-0.nix`
- `modules/ssdinarch/instances/ssdinarch-0.disko.nix`

The host should be minimal but installable through the shared tasks.

### 6. Existing hosts were migrated

- `cache-vultr` is now `cache-0` under `modules/cache/instances/`.
- `recover_0` is now `recover-0` under `modules/recover/instances/`.

### 7. README is still missing / unfinished

A proper `README.md` is needed and must document:

- architecture principles briefly
- `devenv`-only UX
- `devenv tasks run deployment:install-system --input host=<host>`
- `devenv tasks run deployment:update-system --input host=<host>`
- `devenv test`
- SecretSpec note and Enpass operator workflow
- current supported hosts

A previous attempt to write `README.md` hit a connector issue saying `sha` was required, likely because the file already exists and needs an update rather than create.
Use fetch + update flow or tree/commit flow in the next conversation.

### 8. CI is not finished

Need `.github/workflows/test.yml` that uses `devenv` only.

Intended direction:

- checkout repo
- install devenv
- run `devenv test`

Optionally add shellcheck through `devenv test` rather than as a separate external CI step, to preserve the single interface rule.

### 9. CI passing is not yet guaranteed

At the end of the session, CI had not been fully created and the repo had not been validated end-to-end.
Do not claim CI is passing until the branch is updated and checked.

## Current repo facts

- The repo no longer keeps a root `flake.nix` or `flake.lock`; deployments use a temporary flake generated by scripts.
- Existing setups were removed in favor of `modules/` plus temporary flake generation in deployment scripts.

These facts matter if continuing the migration of legacy hosts.

## Recommended next steps in a new conversation

1. Open `WIP-CONTINUE.md` first.
2. Inspect current branch contents on `devenv-2-migration`.
3. Update `AGENTS.md` to match the final conventions exactly.
4. Verify current devenv docs for:
   - task syntax
   - test integration syntax
   - SecretSpec enablement syntax in `devenv.yaml`
5. Fix `devenv.yaml`.
6. Fix `modules/deployment/devenv.nix`.
7. Update existing `README.md` instead of trying to create it.
8. Add CI workflow and make sure it calls only `devenv`.
9. Only then claim CI is passing.

## Explicit warnings for the next assistant

- Do not deliver file contents to the user instead of editing the repository when the connector can edit the repo.
- Use the repo branch directly.
- Be careful with `create_file` versus updating existing files.
- If a file already exists, fetch its current state first and use an update-capable flow.
- Keep the user-visible interface restricted to `devenv`.
