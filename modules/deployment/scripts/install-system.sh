#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

HOST="${1:-}"
VALIDATE_ONLY="false"

if [ -n "${DEVENV_TASK_INPUT:-}" ]; then
  INPUT_HOST="$(printf '%s' "$DEVENV_TASK_INPUT" | jq -r '.host // empty')"
  if [ -n "$INPUT_HOST" ]; then
    HOST="$INPUT_HOST"
  fi
  VALIDATE_ONLY="$(printf '%s' "$DEVENV_TASK_INPUT" | jq -r '.validate_only // false')"
fi

if [ -z "$HOST" ]; then
  echo "usage: devenv tasks run deployment:install-system --input host=<host>"
  exit 1
fi

if [[ "$HOST" == *"/"* || "$HOST" == *".."* || ! "$HOST" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "invalid host: $HOST"
  exit 1
fi

find_instance_path() {
  local host="$1"
  local -a matches=()
  while IFS= read -r match; do
    matches+=("$match")
  done < <(find "$REPO_ROOT/modules" -path "*/instances/${host}.nix" -print)

  if [ "${#matches[@]}" -eq 0 ]; then
    echo "unknown host: $host"
    return 1
  fi

  if [ "${#matches[@]}" -gt 1 ]; then
    echo "ambiguous host: $host"
    printf '%s\n' "${matches[@]}"
    return 1
  fi

  printf '%s\n' "${matches[0]}"
}

INSTANCE_PATH="$(find_instance_path "$HOST")"
INSTANCE_DIR="$(dirname "$INSTANCE_PATH")"
DOMAIN_DIR="$(dirname "$INSTANCE_DIR")"

if [ ! -f "$DOMAIN_DIR/machine.nix" ]; then
  echo "missing machine.nix for host: $HOST"
  exit 1
fi

if [ "$VALIDATE_ONLY" = "true" ]; then
  exit 0
fi

DISKO_PATH="${INSTANCE_PATH%.nix}.disko.nix"
if [ -f "$DISKO_PATH" ]; then
  if ! command -v disko >/dev/null 2>&1; then
    echo "disko not found in PATH; install disko before running install-system"
    exit 1
  fi
  sudo disko --mode destroy,format,mount "$DISKO_PATH"
fi

sudo mkdir -p /mnt/etc/nixos
sudo rsync -a --delete \
  --exclude=.git/ \
  --exclude=.devenv/ \
  --exclude=.direnv/ \
  --exclude=result \
  --exclude=result-* \
  --exclude=control.socket \
  "$REPO_ROOT/" /mnt/etc/nixos/

sudo nixos-install -I nixos-config="/mnt/etc/nixos/${INSTANCE_PATH#"$REPO_ROOT/"}"
