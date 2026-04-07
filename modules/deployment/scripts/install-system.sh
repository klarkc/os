#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=""
HOST=""
VALIDATE_ONLY="false"
TARGET_SSH=""
TARGET_PORT="22"
TARGET_DISK=""
TARGET_IMAGE=""

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
      echo "usage: install-system [host] [--repo-root <path>]"
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
  TARGET_SSH="$(printf '%s' "$DEVENV_TASK_INPUT" | jq -r '.target_ssh // empty')"
  INPUT_TARGET_PORT="$(printf '%s' "$DEVENV_TASK_INPUT" | jq -r '.target_port // empty')"
  if [ -n "$INPUT_TARGET_PORT" ]; then
    TARGET_PORT="$INPUT_TARGET_PORT"
  fi
  TARGET_DISK="$(printf '%s' "$DEVENV_TASK_INPUT" | jq -r '.target_disk // empty')"
  TARGET_IMAGE="$(printf '%s' "$DEVENV_TASK_INPUT" | jq -r '.target_image // empty')"
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
  echo "usage: devenv tasks run deployment:install-system --input host=<host> [--input target_ssh=<user@host>] [--input target_disk=<path>] [--input target_image=<path>]"
  echo "or: install-system [host] [--repo-root <path>]"
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

IMAGE_TMP_DIR=""
cleanup() {
  if [ -n "$IMAGE_TMP_DIR" ]; then
    rm -rf "$IMAGE_TMP_DIR"
  fi
}
trap cleanup EXIT

DISKO_MODULE="$(nix-instantiate --eval --strict "$SYSTEM_NIX" \
  --argstr host "$HOST" \
  --arg root "$REPO_ROOT" \
  -A diskoModule 2>/dev/null | tr -d '"')"

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
    NIXOS_SYSTEM_PATH="$(nix-build "$SYSTEM_NIX" --argstr host "$HOST" --arg root "$REPO_ROOT" -A system --no-out-link)"
    nixos-install --root /mnt --system "$NIXOS_SYSTEM_PATH"
    exit 0
  fi

  if [ -n "$TARGET_IMAGE" ]; then
    if ! grep -q "imageSize" "$DISKO_MODULE"; then
      echo "target_image requires imageSize in ${DISKO_MODULE}"
      exit 1
    fi

    IMAGE_TMP_DIR="$(mktemp -d)"
    IMAGE_SCRIPT="$(nix-build "$SYSTEM_NIX" --argstr host "$HOST" --arg root "$REPO_ROOT" -A imageScript --out-link "${IMAGE_TMP_DIR}/disko-images-script")"
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
DISKO_SCRIPT_PATH="$(nix-build "$SYSTEM_NIX" --argstr host "$HOST" --arg root "$REPO_ROOT" -A diskoScript --no-out-link)"
NIXOS_SYSTEM_PATH="$(nix-build "$SYSTEM_NIX" --argstr host "$HOST" --arg root "$REPO_ROOT" -A system --no-out-link)"
nixos-anywhere --ssh-port "$TARGET_PORT" --store-paths "$DISKO_SCRIPT_PATH" "$NIXOS_SYSTEM_PATH" "$SSH_TARGET"
