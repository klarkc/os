#!/usr/bin/env bash
# Offline contract tests for the exact-commit CI gate; no GitHub token/network.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
target="$here/require-passing-ci.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == api && "$2" == -X && "$3" == GET ]] || exit 3
if [[ -v MOCK_API_FAIL ]]; then exit 2; fi
case "$4" in
  */jobs\?*) printf '%s\n' "$MOCK_JOBS" ;;
  */workflows/test.yml/runs\?*) printf '%s\n' "$MOCK_RUNS" ;;
  *) exit 4 ;;
esac
MOCK
chmod 700 "$scratch/gh"
export PATH="$scratch:$PATH"
export GH_TOKEN=fixture GITHUB_REPOSITORY=klarkc/os GITHUB_REF=refs/heads/main
export CI_GATE_ATTEMPTS=1 CI_GATE_PAUSE=0
export GITHUB_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export MOCK_RUNS='{"workflow_runs":[{"id":91,"status":"completed","conclusion":"success","head_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","head_branch":"main","event":"push","head_repository":{"full_name":"klarkc/os"}}]}'
export MOCK_JOBS='{"total_count":3,"jobs":[{"name":"security","status":"completed","conclusion":"success"},{"name":"format-policy","status":"completed","conclusion":"success"},{"name":"nix","status":"completed","conclusion":"success"}]}'
pass() {
  if ! bash "$target" "$GITHUB_SHA" >"$scratch/output" 2>&1; then
    echo "Unexpected gate failure: $1" >&2
    cat "$scratch/output" >&2
    exit 1
  fi
}
blocked() {
  if bash "$target" "$GITHUB_SHA" >"$scratch/output" 2>&1; then
    echo "Unexpected CI bypass: $1" >&2
    exit 1
  fi
}
pass "all required jobs success"
MOCK_RUNS='{"workflow_runs":[]}' blocked "no matching run"
MOCK_RUNS='{"workflow_runs":[{"id":91,"status":"completed","conclusion":"failure","head_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","head_branch":"main","event":"push","head_repository":{"full_name":"klarkc/os"}}]}' blocked "failed Test run"
MOCK_RUNS='{"workflow_runs":[{"id":91,"status":"in_progress","conclusion":null,"head_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","head_branch":"main","event":"push","head_repository":{"full_name":"klarkc/os"}}]}' blocked "incomplete Test run"
MOCK_RUNS='{"workflow_runs":[{"id":91,"status":"completed","conclusion":"success","head_sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","head_branch":"main","event":"push","head_repository":{"full_name":"klarkc/os"}}]}' blocked "wrong SHA"
MOCK_RUNS='{"workflow_runs":[{"id":91,"status":"completed","conclusion":"success","head_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","head_branch":"feature","event":"push","head_repository":{"full_name":"klarkc/os"}}]}' blocked "wrong branch"
MOCK_JOBS='{"total_count":3,"jobs":[{"name":"security","status":"completed","conclusion":"success"},{"name":"format-policy","status":"completed","conclusion":"skipped"},{"name":"nix","status":"completed","conclusion":"success"}]}' blocked "skipped required job"
MOCK_JOBS='{"total_count":2,"jobs":[{"name":"security","status":"completed","conclusion":"success"},{"name":"nix","status":"completed","conclusion":"success"}]}' blocked "missing required job"
MOCK_JOBS='{"total_count":4,"jobs":[{"name":"security","status":"completed","conclusion":"success"},{"name":"format-policy","status":"completed","conclusion":"success"},{"name":"nix","status":"completed","conclusion":"success"},{"name":"unexpected","status":"completed","conclusion":"success"}]}' blocked "unreviewed CI job"
MOCK_RUNS='not json' blocked "invalid API response"
MOCK_API_FAIL=1 blocked "API outage"
GITHUB_REF=refs/heads/feature blocked "non-main source"
GITHUB_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb blocked "mismatched event SHA"
echo "PASS: exact-commit CI gate fail-closed contract"
