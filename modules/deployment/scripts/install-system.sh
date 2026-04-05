#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

HOST="${1:-}"
VALIDATE_ONLY="false"
TARGET_SSH=""
TARGET_PORT="22"
TARGET_DISK=""
TARGET_IMAGE=""

if [ -n "${DEVENV_TASK_INPUT:-}" ]; then
  INPUT_HOST="$(printf '%s' "$DEVENV_TASK_INPUT" | jq -r '.host // empty')"
  if [ -n "$INPUT_HOST" ]; then
    HOST="$INPUT_HOST"
  fi

  VALIDATE_ONLY="$(printf '%s' "$DEVENV_TASK_INPUT" | jq -r '.validate_only // false')"
  TARGET_SSH="$(printf '%s' "$DEVENV_TASK_INPUT" | jq -r '.target_ssh // empty')"
  INPUT_TARGET_PORT="$(printf '%s' "$DEVENV_TASK_INPUT" | jq -r '.target_port // empty')"
  if [ -n "$INPUT_TARGET_PORT" ]; then
    TARGET_PORT="$INPUT_TARGET_PORT"
  fi
  TARGET_DISK="$(printf '%s' "$DEVENV_TASK_INPUT" | jq -r '.target_disk // empty')"
  TARGET_IMAGE="$(printf '%s' "$DEVENV_TASK_INPUT" | jq -r '.target_image // empty')"
fi

if [ -z "$HOST" ]; then
  echo "usage: devenv tasks run deployment:install-system --input host=<host> [--input target_ssh=<user@host>] [--input target_disk=<path>] [--input target_image=<path>]"
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

TARGET_KIND_COUNT=0
if [ -n "$TARGET_SSH" ]; then
  TARGET_KIND_COUNT=$((TARGET_KIND_COUNT + 1))
fi
if [ -n "$TARGET_DISK" ]; then
  TARGET_KIND_COUNT=$((TARGET_KIND_COUNT + 1))
fi
if [ -n "$TARGET_IMAGE" ]; then
  TARGET_KIND_COUNT=$((TARGET_KIND_COUNT + 1))
fi

if [ "$TARGET_KIND_COUNT" -gt 1 ]; then
  echo "choose only one install target: target_ssh, target_disk, or target_image"
  exit 1
fi

if [ "$VALIDATE_ONLY" = "true" ]; then
  exit 0
fi

if ! command -v nixos-anywhere >/dev/null 2>&1; then
  if [ -z "$TARGET_DISK" ] && [ -z "$TARGET_IMAGE" ]; then
    echo "nixos-anywhere not found in PATH; ensure it is available in devenv"
    exit 1
  fi
fi

TMP_FLAKE_DIR="$(mktemp -d)"
IMAGE_TMP_DIR=""
cleanup() {
  rm -rf "$TMP_FLAKE_DIR"
  if [ -n "$IMAGE_TMP_DIR" ]; then
    rm -rf "$IMAGE_TMP_DIR"
  fi
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

if [ -n "$TARGET_DISK" ] || [ -n "$TARGET_IMAGE" ]; then
  if [ "$(id -u)" -ne 0 ]; then
    echo "local install targets must be run as root"
    exit 1
  fi

  if [ ! -f "$DISKO_MODULE" ]; then
    echo "missing disko module for local install: $DISKO_MODULE"
    exit 1
  fi

  if ! command -v nix >/dev/null 2>&1; then
    echo "nix not found in PATH"
    exit 1
  fi

  if [ -n "$TARGET_DISK" ]; then
    if [ ! -b "$TARGET_DISK" ]; then
      echo "target_disk is not a block device: $TARGET_DISK"
      exit 1
    fi

    DISKO_DEVICES="$(grep -E 'device\s*=\s*"' "$DISKO_MODULE" | sed -E 's/.*device\s*=\s*"([^"]+)".*/\1/' | tr '\n' ' ' || true)"
    if [ -n "$DISKO_DEVICES" ] && [[ " $DISKO_DEVICES " != *" $TARGET_DISK "* ]]; then
      echo "target_disk ($TARGET_DISK) does not match disko device(s): $DISKO_DEVICES"
      exit 1
    fi

    if command -v disko >/dev/null 2>&1; then
      disko --mode destroy,format,mount "$DISKO_MODULE"
    else
      nix --experimental-features "nix-command flakes" run github:nix-community/disko/latest -- \
        --mode destroy,format,mount "$DISKO_MODULE"
    fi

    if ! command -v nixos-install >/dev/null 2>&1; then
      echo "nixos-install not found in PATH"
      exit 1
    fi

    echo "Installing ${HOST} to ${TARGET_DISK}"
    echo "Using temp flake: ${TMP_FLAKE_DIR}#${HOST}"
    nixos-install --root /mnt --flake "${TMP_FLAKE_DIR}#${HOST}"
    exit 0
  fi

  if [ -n "$TARGET_IMAGE" ]; then
    if ! grep -q "imageSize" "$DISKO_MODULE"; then
      echo "target_image requires imageSize in ${DISKO_MODULE}"
      exit 1
    fi

    IMAGE_TMP_DIR="$(mktemp -d)"
    nix --experimental-features "nix-command flakes" build \
      "${TMP_FLAKE_DIR}#nixosConfigurations.${HOST}.config.system.build.diskoImagesScript" \
      --out-link "${IMAGE_TMP_DIR}/disko-images-script"
    IMAGE_SCRIPT="$(readlink -f "${IMAGE_TMP_DIR}/disko-images-script")"
    (cd "$IMAGE_TMP_DIR" && "$IMAGE_SCRIPT")

    IMAGE_COUNT="$(find "$IMAGE_TMP_DIR" -maxdepth 1 -name "*.raw" | wc -l | tr -d ' ')"
    if [ "$IMAGE_COUNT" -eq 0 ]; then
      echo "no image produced by diskoImagesScript"
      exit 1
    fi

    if [ "$IMAGE_COUNT" -gt 1 ]; then
      if [ ! -d "$TARGET_IMAGE" ]; then
        echo "multiple images produced; specify a directory target_image to capture all outputs"
        exit 1
      fi
      mkdir -p "$TARGET_IMAGE"
      find "$IMAGE_TMP_DIR" -maxdepth 1 -name "*.raw" -exec mv {} "$TARGET_IMAGE"/ \;
      echo "Wrote images to ${TARGET_IMAGE}"
      exit 0
    fi

    IMAGE_FILE="$(find "$IMAGE_TMP_DIR" -maxdepth 1 -name "*.raw" -print | head -n 1 || true)"
    if [ -d "$TARGET_IMAGE" ]; then
      TARGET_IMAGE_PATH="${TARGET_IMAGE}/$(basename "$IMAGE_FILE")"
    else
      TARGET_IMAGE_PATH="$TARGET_IMAGE"
    fi

    mkdir -p "$(dirname "$TARGET_IMAGE_PATH")"
    mv "$IMAGE_FILE" "$TARGET_IMAGE_PATH"
    echo "Wrote image to ${TARGET_IMAGE_PATH}"
    exit 0
  fi
fi

TARGET_USER="${DEPLOY_TARGET_USER:-root}"
TARGET_HOST="${DEPLOY_TARGET_HOST:-$HOST}"
if [ -n "$TARGET_SSH" ]; then
  SSH_TARGET="$TARGET_SSH"
else
  if [ -z "$TARGET_HOST" ]; then
    echo "missing DEPLOY_TARGET_HOST, target_ssh, or host argument"
    exit 1
  fi
  SSH_TARGET="${TARGET_USER}@${TARGET_HOST}"
fi

echo "Installing ${HOST} to ${SSH_TARGET}:${TARGET_PORT}"
echo "Using temp flake: ${TMP_FLAKE_DIR}#${HOST}"

nixos-anywhere --ssh-port "$TARGET_PORT" --flake "${TMP_FLAKE_DIR}#${HOST}" "$SSH_TARGET"
