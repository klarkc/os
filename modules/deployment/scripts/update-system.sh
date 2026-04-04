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
  echo "usage: devenv tasks run deployment:update-system --input host=<host>"
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

if ! command -v ssh >/dev/null 2>&1; then
  echo "ssh not found in PATH; ensure openssh is available in devenv"
  exit 1
fi

if ! command -v nixos-anywhere >/dev/null 2>&1; then
  echo "nixos-anywhere not found in PATH; ensure it is available in devenv"
  exit 1
fi

TARGET_USER="${DEPLOY_TARGET_USER:-root}"
TARGET_HOST="${DEPLOY_TARGET_HOST:-$HOST}"
TARGET_PORT="${DEPLOY_TARGET_PORT:-22}"

if [ -z "$TARGET_HOST" ]; then
  echo "missing DEPLOY_TARGET_HOST or host argument"
  exit 1
fi

SSH_TARGET="${TARGET_USER}@${TARGET_HOST}"
TMP_FLAKE_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_FLAKE_DIR"
}
trap cleanup EXIT

SHARED_MODULE="${REPO_ROOT}/modules/shared/system.nix"
INSTANCE_MODULE="${INSTANCE_PATH}"
DISKO_MODULE="${INSTANCE_PATH%.nix}.disko.nix"

cat > "${TMP_FLAKE_DIR}/flake.nix" <<EOF
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, disko, ... }:
    let
      system = "x86_64-linux";
      modules =
        [ ${SHARED_MODULE} ${INSTANCE_MODULE} ]
        ++ (if builtins.pathExists ${DISKO_MODULE} then [
          disko.nixosModules.disko
          ${DISKO_MODULE}
        ] else
          [ ]);
    in {
      nixosConfigurations."${HOST}" = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = modules;
      };
    };
}
EOF

DISKO_ARGS=()
if [ -f "$DISKO_MODULE" ]; then
  DISKO_ARGS+=(--disko-mode mount)
fi

echo "Updating ${HOST} on ${SSH_TARGET}:${TARGET_PORT}"
echo "Using temp flake: ${TMP_FLAKE_DIR}#${HOST}"

nixos-anywhere --ssh-port "$TARGET_PORT" --phases install "${DISKO_ARGS[@]}" --flake "${TMP_FLAKE_DIR}#${HOST}" "$SSH_TARGET"
