# Documentation continuation notes

This file continues the docs WIP for the `devenv-2-migration` branch and corrects a few assumptions in `WIP-CONTINUE.md` based on the current branch state.

## Verified current state

These items are already present on the branch and do not need to be described as missing anymore:

- `README.md` already exists and documents the `devenv`-only interface.
- `.github/workflows/test.yml` already exists and runs `nix run github:cachix/devenv -- test`.
- `devenv.yaml` already imports the current domains and enables `secretspec` globally.
- `modules/deployment/devenv.nix` already wires tasks to scripts under `modules/deployment/scripts/`.

## Remaining docs work

### 1. Tighten `AGENTS.md`

`AGENTS.md` is directionally correct, but it still mixes branch rules with broader preferences that are not yet verified in this repo.

Recommended edits:

- keep the hard rules that match the branch layout
- keep the `devenv`-only interface requirement
- keep the `modules/<domain>/` structure and script/test co-location rules
- keep the rule that `.test.sh` files are loaded by a domain `devenv.nix`
- remove or soften advice that is not yet validated in this repo workflow
- explicitly document that current tests are aggregated through `enterTest`

### 2. Refine `README.md`

`README.md` exists, but it can be improved to better match the migration goals.

Recommended edits:

- explain that deployment tasks read `host` from `DEVENV_TASK_INPUT`
- mention that scripts are implementation details behind `devenv tasks`
- call out that temporary flakes are generated during install/update
- clarify the current supported hosts and their domain layout
- keep the SecretSpec + Enpass operator note brief and practical

### 3. Update `WIP-CONTINUE.md`

`WIP-CONTINUE.md` should be refreshed so it distinguishes between:

- work that is already done on the branch
- work that is implemented but still needs verification
- work that is still actually missing

In particular, it should no longer imply that README or CI are absent.

## Suggested truth-based wording for the main open items

### Still worth verifying

- Whether the `secretspec` block in `devenv.yaml` matches current devenv expectations.
- Whether `enterTest` is the intended long-term test registration mechanism for this repo.
- Whether the deployment task/input shape is exactly the preferred contemporary devenv task syntax.
- Whether install/update behavior is correct end-to-end for all declared hosts.

### Still worth documenting better

- Architecture principles for the domain-based layout.
- Why humans and CI should use `devenv` only.
- The host naming convention: `<domain>-<number>`.
- The install/update interface and `DEPLOY_TARGET_*` overrides.
- Secret handling expectations for operators.

## Practical next commit after this file

A sensible follow-up docs commit would be:

```text
docs: align README and AGENTS with current devenv migration state
```

And that commit should focus only on:

- `README.md`
- `AGENTS.md`
- `WIP-CONTINUE.md`

without mixing in implementation changes.
