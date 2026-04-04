# AGENTS.md

## Architecture principles

### Interface

The only public interface for humans and CI is `devenv`.

Do not expose raw `nix`, `nixos-rebuild`, `nixos-install`, `disko`, or direct script invocation as the primary repository interface.
Do not treat shell scripts as the public UX. Domain scripts are executed behind `devenv` tasks.

### Layout

Organize the repository by explicit domain under `modules/<domain>/`.

Each domain directory must expose a `devenv.nix` entrypoint.
The root `devenv.yaml` imports each domain directory and relies on that implicit `devenv.nix`.

Current domains on this branch include:

- `modules/deployment`
- `modules/shared`
- `modules/ssdinarch`
- `modules/cache`
- `modules/recover`

### Naming

Prefer explicit domain names.

Avoid implicit names such as `default.nix`, `index.*`, or catch-all repository-root folders for major responsibilities.
Avoid unnecessary plurals for domain names.

Model machines with both a definition and an instance.
The domain name is the definition name.
Instances should be named `<domain>-<number>` and correspond to the hostname.
Instance configs live under `modules/<domain>/instances/<instance>.nix`, with optional `modules/<domain>/instances/<instance>.disko.nix` for disk layout.

### Nix vs shell responsibilities

`.nix` files are declarative and are only checked or evaluated.
They are not the direct executable interface.

Executable behavior lives in `.sh` scripts.
Every `.sh` script must have a co-localized `.test.sh` script.

### Script layout

When a domain has executable behavior, place it under `scripts/` inside the domain.

Examples:

- `modules/deployment/scripts/install-system.sh`
- `modules/deployment/scripts/install-system.test.sh`
- `modules/deployment/scripts/update-system.sh`
- `modules/deployment/scripts/update-system.test.sh`

### Task wiring

Tasks should call scripts from their own domain `devenv.nix`.

Example task names:

- `deployment:install-system`
- `deployment:update-system`

### Test loading

Every `.test.sh` must be loaded by a `devenv.nix` module.
The external interface for test execution is always `devenv test`.

On the current branch, shell-based tests are aggregated through `enterTest` in the relevant domain modules.
Do not require users or CI to invoke `*.test.sh` directly.

### Shared system defaults

Maintain shared NixOS defaults in `modules/shared/system.nix` and include that module in every generated system.
Put cross-machine defaults there and remove duplicated settings from per-host modules where practical.

### Secrets

Use SecretSpec through `devenv.yaml` as the repository-wide secrets mechanism.
Do not commit real secrets.

At present, operator-side secret material is handled out of band and documented in the README.

### CI

CI must call `devenv` only.
Repository tests must run through `devenv test`.

### Commits

Avoid one giant commit. Commit small, feature-focused changes as you go.
Follow `COMMIT_GUIDELINES.md` for commit structure.
