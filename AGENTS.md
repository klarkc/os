# AGENTS.md

## Architecture principles

### Interface

The only public interface for humans and CI is `devenv`.

Do not expose `nix`, `nixos-rebuild`, `nixos-install`, `disko`, or ad-hoc shell entrypoints as the primary interface.

When running `devenv` in CI, use the latest `devenv` via `nix run` rather than relying on a pinned global install.
Prefer the Determinate Nix GitHub Action and `magic-nix-cache-action` for CI setup.

### Always-on workflow rules

- Read target files before editing.
- Match existing whitespace/indentation exactly when editing.
- Prefer `devenv` commands and documented tasks over raw `nix`.
- Do not run `devenv test` while `devenv up` is running or vice-versa.
- Run the most local/fast relevant tests first.
- For `devenv test`, redirect output to a file (no stdout/`tee`).
- When given a new summary, sync with `docs/wip.md` (if it exists) before taking any other action.

### Layout

Organize the repository by explicit domain under `modules/<domain>/`.

Each domain directory must expose a `devenv.nix` entrypoint.
The root `devenv.yaml` imports each domain directory and relies on that implicit `devenv.nix`.

Examples:

- `modules/deployment/devenv.nix`
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

- `modules/deployment/scripts/install-system.sh`
- `modules/deployment/scripts/install-system.test.sh`
- `modules/deployment/scripts/update-system.sh`
- `modules/deployment/scripts/update-system.test.sh`

### Test loading

Every `.test.sh` must be loaded by a `devenv.nix` module.
The external interface for test execution is always `devenv test`.

Do not require users or CI to call `*.test.sh` directly.

Prefer the `enterTest` hook for test registration; avoid a custom/global test runner since the devenv module system already aggregates tests.

### Secrets

Use SecretSpec through `devenv.yaml` as the repository-wide secrets mechanism.
Do not create extra secrets modules unless there is a concrete need that cannot be solved by the global configuration.

Do not commit real secrets.

### Host domains

Machine-specific domains live under `modules/<domain>/`.
Keep host-specific declarative files co-localized, for example:

- `machine.nix`

Only add files when there is a concrete responsibility for them.

Model machines with both a definition and an instance.
The domain name is the definition name.
Instances should be named `<domain>-<number>` and correspond to the hostname (e.g., `recover` vs `recover-0`, `ssdinarch` vs `ssdinarch-0`).
Do not use instance names (like `recover-0`) as domain names.
Instance configs live under `modules/<domain>/instances/<instance>.nix`, with optional `modules/<domain>/instances/<instance>.disko.nix` for disk layout.

### CI

CI must call `devenv` only.
Repository tests must run through `devenv test`.

For install/update scripts, avoid manual Nix steps where a helper exists; check `../Solo/solosig` for the preferred helper workflow.

### Task naming

Tasks must use `namespace:name` format (e.g., `deployment:install-system`).

### Commits

Avoid one giant commit. Commit small, feature-focused changes as you go.
Follow the repository commit guidelines; if none exist, create them using the current conventions and then follow them.

If asked to commit, share the exact commit message first and include a trailer: `Assisted-by: [Model Name] via <AgentName>`.
Use `refactor:` for structural moves and `chore:` for infra-only changes.
Include a `BREAKING CHANGE:` block with migration steps when required.

### Devenv notes

- Use `devenv up -d` for running services in background.
- Never invoke `devenv` from inside a devenv task; use `devenv-tasks` instead.
- Use `config.git.root` for repo-root paths in Nix.

### Testing/CI notes

- Suggested sequence: lint/hooks → targeted tests → `devenv test`.
- Prefer running `devenv tasks run devenv:git-hooks:run` to execute hooks.
- CI note: prefer `devenv outputs` over `devenv shell` in CI.
- CI note: use deterministic `devenv build --out-link` paths when applicable.
