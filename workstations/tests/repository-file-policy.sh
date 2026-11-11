#!/usr/bin/env bash
set -euo pipefail
mode="${1:---ci}"
case "$mode" in --ci|--hook|--selftest) ;; *) echo 'Usage: repository-file-policy.sh [--ci|--hook|--selftest]' >&2; exit 2 ;; esac
allowed() {
  case "$1" in
    AGENTS.md|README.md|LICENSE|.gitignore|flake.lock) return 0 ;;
    .github/*)
      case "$1" in *.yml|*.yaml) return 0 ;; *) return 1 ;; esac
      ;;
    *.nix|*.sh) return 0 ;;
    *) return 1 ;;
  esac
}
if [[ "$mode" == --selftest ]]; then
  for item in AGENTS.md README.md LICENSE .gitignore flake.lock flake.nix src/tool.sh .github/workflows/test.yml .github/dependabot.yaml; do
    allowed "$item" || exit 1
  done
  for item in CHANGELOG.md .github/known_hosts .github/script.sh .github/module.nix notes.md docs/README.md workstations/flake.lock tests/check.py; do
    if allowed "$item"; then echo "Unexpected accepted path: $item" >&2; exit 1; fi
  done
  echo "PASS: format-policy selftest"
  exit 0
fi
repo=$(git rev-parse --show-toplevel) || exit 2
cd "$repo"
bad=0
if [[ "$mode" == --ci ]]; then
  while IFS= read -r -d '' file; do
    if ! allowed "$file"; then printf 'ERROR: disallowed tracked path: %s\n' "$file" >&2; bad=$((bad+1)); fi
  done < <(git ls-files -z)
else
  while IFS= read -r -d '' file; do
    if ! allowed "$file"; then printf 'WARNING: staged file outside policy: %s\n' "$file" >&2; bad=$((bad+1)); fi
  done < <(git diff --cached --name-only --diff-filter=ACMR -z)
fi
if (( bad > 0 )); then
  if [[ "$mode" == --ci ]]; then
    printf 'FAIL: %s tracked file-format violations. Migrate safely before release.\n' "$bad" >&2
    exit 1
  fi
  printf 'WARNING: %s staged violations. CI will reject them.\n' "$bad" >&2
else
  echo "PASS: file format policy ($mode)"
fi
