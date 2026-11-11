#!/usr/bin/env bash
# Fail-closed dependency: a deployment SHA requires a complete successful Test run.
# This is read-only GitHub API access; never deploy or mutate an instance here.
set -euo pipefail
block() {
  printf 'BLOCKED: exact-commit Test CI: %s\n' "$*" >&2
  exit 1
}
[[ "$#" -eq 1 ]] || block "expected one Git commit SHA"
target="$1"
[[ "$target" =~ ^[0-9a-f]{40}$ ]] || block "invalid commit SHA"
[[ -v GITHUB_SHA && "$GITHUB_SHA" == "$target" ]] || block "commit does not match GitHub event"
[[ -v GITHUB_REPOSITORY && "$GITHUB_REPOSITORY" == klarkc/os ]] || block "unexpected repository"
[[ -v GITHUB_REF && "$GITHUB_REF" == refs/heads/main ]] || block "only main may deploy"
[[ -v GH_TOKEN && -n "$GH_TOKEN" ]] || block "missing GitHub Actions read token"
command -v gh >/dev/null || block "gh CLI missing"
command -v jq >/dev/null || block "jq missing"
attempts=60
pause=10
if [[ -v CI_GATE_ATTEMPTS ]]; then attempts="$CI_GATE_ATTEMPTS"; fi
if [[ -v CI_GATE_PAUSE ]]; then pause="$CI_GATE_PAUSE"; fi
[[ "$attempts" =~ ^[1-9][0-9]*$ ]] || block "invalid attempt limit"
[[ "$pause" =~ ^[0-9]+$ ]] || block "invalid polling delay"
(( attempts <= 60 )) || block "attempt limit too high"
for ((i=1; i<=attempts; i++)); do
  if ! runs="$(gh api -X GET "repos/$GITHUB_REPOSITORY/actions/workflows/test.yml/runs?head_sha=$target&branch=main&event=push&per_page=30")"; then
    block "GitHub API unavailable while reading Test runs"
  fi
  if ! record="$(jq -er --arg sha "$target" --arg repo "$GITHUB_REPOSITORY" '
    ([.workflow_runs[]? | select(
       .head_sha == $sha
       and .head_branch == "main"
       and .event == "push"
       and .head_repository.full_name == $repo
    )] | sort_by(.id) | last) as $run
    | if $run == null then "missing|none|none"
      else [$run.status, ($run.conclusion // "none"), ($run.id | tostring)] | join("|")
      end
  ' <<<"$runs")"; then
    block "malformed workflow run response"
  fi
  IFS='|' read -r status conclusion run_id <<<"$record"
  if [[ "$status" == completed ]]; then
    [[ "$conclusion" == success ]] || block "Test run $run_id concluded $conclusion"
    if ! jobs="$(gh api -X GET "repos/$GITHUB_REPOSITORY/actions/runs/$run_id/jobs?filter=latest&per_page=100")"; then
      block "GitHub API unavailable while reading Test jobs"
    fi
    if ! jq -e '
      .total_count == 3
      and (([.jobs[].name] | sort) == ["format-policy", "nix", "security"])
      and all(.jobs[]; .status == "completed" and .conclusion == "success")
    ' >/dev/null <<<"$jobs"; then
      block "Test run $run_id has missing, skipped, failed or unverified required jobs"
    fi
    printf 'PASS: Test run %s at exact commit %s; all required jobs succeeded\n' "$run_id" "$target"
    exit 0
  fi
  case "$status" in
    missing|queued|in_progress|requested|waiting|pending) ;;
    *) block "unexpected Test status $status (run $run_id)" ;;
  esac
  if ((i < attempts)); then sleep "$pause"; fi
done
block "no completed successful Test run for commit $target after $attempts checks"
