#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=""
HOST=""
VALIDATE_ONLY="false"
DETECTED_HOST=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-root)
      if [ "$#" -lt 2 ]; then
        echo "missing value for --repo-root"
        exit 1
      fi
      REPO_ROOT="$2"
      shift 2
      ;;
    --help)
      echo "usage: update-system [host] [--repo-root <path>]"
      exit 0
      ;;
    -*)
      echo "unknown argument: $1"
      exit 1
      ;;
    *)
      if [ -z "$HOST" ]; then
        HOST="$1"
        shift
      else
        echo "unexpected argument: $1"
        exit 1
      fi
      ;;
  esac
done

if [ -n "${DEVENV_TASK_INPUT:-}" ]; then
  INPUT_HOST="$(printf '%s' "$DEVENV_TASK_INPUT" | jq -r '.host // empty')"
  if [ -n "$INPUT_HOST" ]; then
    HOST="$INPUT_HOST"
  fi
  VALIDATE_ONLY="$(printf '%s' "$DEVENV_TASK_INPUT" | jq -r '.validate_only // false')"
fi

if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT="$(pwd)"
  echo "WARN: --repo-root not provided; assuming current directory is the repo root: ${REPO_ROOT}" >&2
fi

if [ ! -d "$REPO_ROOT/modules" ]; then
  echo "repo root does not look valid: ${REPO_ROOT}"
  exit 1
fi

if [ -z "$HOST" ]; then
  if command -v hostname >/dev/null 2>&1; then
    DETECTED_HOST="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
  fi
  if [ -z "$DETECTED_HOST" ] && [ -f /etc/hostname ]; then
    DETECTED_HOST="$(cat /etc/hostname)"
  fi
  DETECTED_HOST="${DETECTED_HOST%%.*}"
  HOST="$DETECTED_HOST"
fi

if [ -z "$HOST" ]; then
  echo "usage: devenv tasks run deployment:update-system [--input host=<host>]"
  echo "or: update-system [host] [--repo-root <path>]"
  exit 1
fi

if [ -n "$DETECTED_HOST" ] && [ -n "${INPUT_HOST:-}" ] && [ "$INPUT_HOST" != "$DETECTED_HOST" ]; then
  echo "host input ($INPUT_HOST) does not match local hostname ($DETECTED_HOST)"
  exit 1
fi

if [[ "$HOST" == *"/"* || "$HOST" == *".."* || ! "$HOST" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "invalid host: $HOST"
  exit 1
fi

SYSTEM_NIX="${REPO_ROOT}/modules/deployment/nixos-system.nix"
if [ ! -f "$SYSTEM_NIX" ]; then
  echo "missing deployment system evaluator: $SYSTEM_NIX"
  exit 1
fi

if ! nix-instantiate --eval --strict "$SYSTEM_NIX" \
  --argstr host "$HOST" \
  --arg root "$REPO_ROOT" \
  -A machineInfo.system >/dev/null 2>&1; then
  echo "unknown host: $HOST"
  exit 1
fi

if [ "$VALIDATE_ONLY" = "true" ]; then
  exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "update-system must be run as root on the installed machine"
  exit 1
fi

if ! command -v nixos-rebuild >/dev/null 2>&1; then
  echo "nixos-rebuild not found in PATH"
  exit 1
fi

echo "Updating ${HOST} from ${REPO_ROOT}"
NIXOS_SYSTEM_PATH="$(nix-build "$SYSTEM_NIX" --argstr host "$HOST" --arg root "$REPO_ROOT" -A system --no-out-link)"
nixos-rebuild switch --store-path "$NIXOS_SYSTEM_PATH"
