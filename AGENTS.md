# AGENTS.md

## Architecture principles

### Interface

The only public interface for humans and CI is `devenv`.

Do not expose `nix`, `nixos-rebuild`, `nixos-install`, `disko`, or ad-hoc shell entrypoints as the primary interface.

### Layout

Organize the repository by explicit domain under `modules/<domain>/`.

Each domain directory must expose a `devenv.nix` entrypoint.
The root `devenv.yaml` imports each domain directory and relies on that implicit `devenv.nix`.

Examples:

- `modules/install-system/devenv.nix`
- `modules/update-system/devenv.nix`
- `modules/ssdinarch/devenv.nix`

### Naming

Prefer explicit domain names.

Avoid implicit names such as `default.nix`, `index.*`, or catch-all layout folders like `hosts/`, `tasks/`, or `scripts/` at the repository root.

Avoid unnecessary plurals for domain names.

### Nix vs shell responsibilities

`.nix` files are declarative and are only checked/evaluated.
They are not directly tested.

Executable behavior must live in `.sh` scripts.
Every `.sh` script must have a co-localized `.test.sh` script.

### Script layout

When a domain has executable behavior, place it under `scripts/` inside the domain.

Examples:

- `modules/install-system/scripts/install-system.sh`
- `modules/install-system/scripts/install-system.test.sh`
- `modules/update-system/scripts/update-system.sh`
- `modules/update-system/scripts/update-system.test.sh`

### Test loading

Every `.test.sh` must be loaded by a `devenv.nix` module.
The external interface for test execution is always `devenv test`.

Do not require users or CI to call `*.test.sh` directly.

### Secrets

Use SecretSpec through `devenv.yaml` as the repository-wide secrets mechanism.
Do not create extra secrets modules unless there is a concrete need that cannot be solved by the global configuration.

Do not commit real secrets.

### Host domains

Machine-specific domains live under `modules/<host>/`.
Keep host-specific declarative files co-localized, for example:

- `machine.nix`
- `disko.nix`

Only add files when there is a concrete responsibility for them.

### CI

CI must call `devenv` only.
Repository tests must run through `devenv test`.
