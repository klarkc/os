# AGENTS.md

## Architecture principles

### Interface

The only public interface for humans and CI is `devenv`.

Do not expose raw `nix`, `nixos-rebuild`, `nixos-install`, `disko`, or direct script invocation as the primary repository interface.
Do not treat shell scripts as the public UX. Domain scripts are executed behind `devenv` tasks.

### Deployment model

The intended deployment split is:

- `install-system`: install to a target
- `update-system`: update from inside an already installed machine

`install-system` should support at least two target classes:

- a remote machine reached over SSH
- a local target such as a disk device or image file

`update-system` should not be modeled as a remote deployment command. Its intended home is the installed machine itself.

If current implementation details still reflect an SSH-oriented update path, treat that as migration state rather than the final architecture.

### Layout

Organize the repository by explicit domain under `modules/<domain>/`.

Each domain directory must expose a `devenv.nix` entrypoint.
The root `devenv.yaml` imports each domain directory and relies on that implicit `devenv.nix`.

### Naming

Prefer explicit domain names.

Avoid implicit names such as `default.nix`, `index.*`, or catch-all repository-root folders for major responsibilities.
Avoid unnecessary plurals for domain names.

Treat a machine as the concrete host instance.
Machine names should be named `<domain>-<number>` and correspond to the hostname.
When using `devenv` machine support, `machines.<name>` should use that concrete machine name directly.
Keep machine files explicit and domain-local, but do not require one fixed path layout.

### Nix vs shell responsibilities

`.nix` files are declarative and are only checked or evaluated.
They are not the direct executable interface.

Executable behavior lives in `.sh` scripts.
Every `.sh` script must have a co-localized `.test.sh` script.

### Script layout

When a domain has executable behavior, place it under `scripts/` inside the domain.

Do not wire repository behavior by calling script files directly from module configuration with raw paths.
Expose domain scripts through `devenv` first, and have tasks and tests call the exposed script names rather than raw script paths.

Always write bash scripts with `writeShellApplication`.
If a script needs dependencies, declare them co-localized with that script or package definition instead of hiding them in unrelated global package lists.
In Nix, group related options into a single object when practical.
Prefer `scripts = { ... };` over repeated top-level assignments like `scripts.a = ...; scripts.b = ...;`.

### Task wiring

Tasks should call scripts from their own domain `devenv.nix`.

For safe local validation of the current migration state, prefer running deployment tasks with `--input validate_only=true` before attempting any real target operation.

### Test loading

Every `.test.sh` must be loaded by a `devenv.nix` module.
The external interface for test execution is always `devenv test`, with shell-based tests aggregated through `enterTest`.

### Shared system defaults

Maintain shared NixOS defaults in `modules/shared/system.nix` and include that module in every generated system.
Put cross-machine defaults there and remove duplicated settings from per-host modules where practical.

### Secrets

Use SecretSpec through `devenv.yaml` as the repository-wide secrets mechanism.
Do not commit real secrets.

At present, operator-side secret material is handled out of band and documented in the README.

### CI

CI must call `devenv` only, and repository tests must run through `devenv test`.

### Validation status

Do not overstate this as final deployment validation. The implementation still needs to be aligned with the intended target-oriented install flow and the in-machine update flow.

### Local testing before commits

Install the pinned `devenv` CLI once:

```bash
nix profile add github:cachix/devenv/v2.0.6
```

Use `devenv` directly for the repository entrypoint:

```bash
devenv <subcommand>
```

Run local tests before committing changes that affect behavior:

```bash
devenv test
```

Examples:

```bash
devenv tasks list
devenv test
```

When running long tests locally, prefer redirecting output to a file:

```bash
devenv test > /tmp/devenv-test.log 2>&1
```

### Commits

Avoid one giant commit. Commit small, feature-focused changes as you go.
Follow `COMMIT_GUIDELINES.md` for commit structure.
