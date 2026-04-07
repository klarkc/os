#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=""

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
      echo "usage: vm-integration-test [--repo-root <path>]"
      exit 0
      ;;
    -*)
      echo "unknown argument: $1"
      exit 1
      ;;
    *)
      echo "unexpected argument: $1"
      exit 1
      ;;
  esac
done

if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT="$(pwd)"
  echo "WARN: --repo-root not provided; assuming current directory is the repo root: ${REPO_ROOT}" >&2
fi

if [ ! -d "$REPO_ROOT/modules" ]; then
  echo "repo root does not look valid: ${REPO_ROOT}"
  exit 1
fi

echo "RUN_VM_INSTANCES=${RUN_VM_INSTANCES:-}"


if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "qemu-system-x86_64 is required for VM integration test"
  exit 1
fi

if [ ! -e /dev/kvm ] || [ ! -w /dev/kvm ]; then
  echo "/dev/kvm is required and must be writable for VM integration test"
  exit 1
fi

find_free_port() {
  local port
  for port in 2222 2223 2224 2225 2226 2227 2228 2229; do
    if ! (exec 3<>/dev/tcp/127.0.0.1/"$port") 2>/dev/null; then
      echo "$port"
      return 0
    fi
  done
  return 1
}

TMP_DIR="$(mktemp -d)"
cleanup() {
  if [ -n "${VM_PID:-}" ] && kill -0 "$VM_PID" 2>/dev/null; then
    kill "$VM_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ssh-keygen -t ed25519 -N "" -f "${TMP_DIR}/vm_key" >/dev/null
VM_SSH_KEY="${TMP_DIR}/vm_key"
VM_SSH_PUB="$(cat "${TMP_DIR}/vm_key.pub")"
VM_SYSTEM_NIX="${REPO_ROOT}/modules/deployment/vm-system.nix"

list_instances() {
  local instance
  for instance in ${DEVENV_VM_INSTANCES:-}; do
    printf '%s\n' "$instance"
  done
}

run_instance_test() {
  local instance="$1"
  echo "Running VM integration test for instance: ${instance}"

  local port
  port="$(find_free_port)"
  if [ -z "$port" ]; then
    echo "no free port available for VM SSH"
    return 1
  fi

  local instance_tmp="${TMP_DIR}/${instance}"
  mkdir -p "$instance_tmp"

  local extra_module="${instance_tmp}/vm-extra.nix"
  cat > "$extra_module" <<EOF
{ lib, modulesPath, pkgs, ... }:
let
  updateSystem = pkgs.writeShellApplication {
    name = "update-system";
    runtimeInputs = [
      pkgs.findutils
      pkgs.jq
      pkgs.nixos-rebuild
    ];
    text = builtins.readFile ${REPO_ROOT}/modules/deployment/scripts/update-system.sh;
  };
in {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/virtualisation/qemu-vm.nix")
    (modulesPath + "/installer/scan/not-detected.nix")
  ];
  environment.systemPackages = [ pkgs.rsync updateSystem ];
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [ "${VM_SSH_PUB}" ];
  nix.settings.experimental-features = lib.mkForce [ "nix-command" "flakes" ];
  virtualisation.forwardPorts = [{
    from = "host";
    host.port = ${port};
    guest.port = 22;
  }];
  virtualisation.graphics = lib.mkForce false;
  virtualisation.memorySize = 2048;
  services.nginx.enable = false;
  services.nix-serve.enable = false;
  security.acme.acceptTerms = false;
}
EOF

  if ! command -v nix-build >/dev/null 2>&1; then
    echo "nix-build is required for VM integration test"
    return 1
  fi

  local out_link="${instance_tmp}/result"
  echo "nix-build ${VM_SYSTEM_NIX} -A ${instance}.config.system.build.vmWithDisko"
  (cd "$instance_tmp" && nix-build \
    "${VM_SYSTEM_NIX}" \
    --out-link "$out_link" \
    --argstr host "${instance}" \
    --argstr extraModulePath "${extra_module}" \
    --arg root "$REPO_ROOT" \
    -A "${instance}.config.system.build.vmWithDisko")

  if [ ! -e "${out_link}/bin" ]; then
    echo "nix-build did not produce a VM build for ${instance}"
    return 1
  fi

  local vm_runner="${out_link}/bin/disko-vm"
  if [ ! -x "$vm_runner" ]; then
    vm_runner="$(find "${out_link}/bin" -maxdepth 1 -type f -name '*vm' | head -n 1 || true)"
  fi
  if [ -z "$vm_runner" ] || [ ! -x "$vm_runner" ]; then
    echo "vm runner not found for ${instance}"
    return 1
  fi

  echo "$vm_runner"
  "$vm_runner" >"${instance_tmp}/vm.log" 2>&1 < /dev/null &
  VM_PID=$!

  SSH_OPTS=(-i "$VM_SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
  SSH_CMD=(ssh -p "$port" -i "$VM_SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

  READY="false"
  for _ in {1..30}; do
    if ssh "${SSH_OPTS[@]}" -p "$port" root@127.0.0.1 true >/dev/null 2>&1; then
      READY="true"
      break
    fi
    sleep 5
  done

  if [ "$READY" != "true" ]; then
    echo "VM did not become reachable over SSH for ${instance}"
    return 1
  fi

  echo "ssh -p ${port} root@127.0.0.1 \"mkdir -p /root/os\""
  ssh "${SSH_OPTS[@]}" -p "$port" root@127.0.0.1 "mkdir -p /root/os"
  echo "rsync -a --delete --exclude .git ${REPO_ROOT}/ root@127.0.0.1:/root/os/ -e ${SSH_CMD[*]}"
  rsync -a --delete --exclude '.git' "$REPO_ROOT/" \
    "root@127.0.0.1:/root/os/" -e "${SSH_CMD[*]}"

  echo "ssh -p ${port} root@127.0.0.1 \"update-system --repo-root /root/os\""
  ssh "${SSH_OPTS[@]}" -p "$port" root@127.0.0.1 \
    "update-system --repo-root /root/os"

  echo "ssh -p ${port} root@127.0.0.1 \"systemctl poweroff\""
  ssh "${SSH_OPTS[@]}" -p "$port" root@127.0.0.1 "systemctl poweroff" || true

  VM_PID=""
  echo "vm integration test passed for ${instance}"
}

instances_to_test=()
if [ -z "${RUN_VM_INSTANCES:-}" ]; then
  while IFS= read -r instance; do
    instances_to_test+=("$instance")
  done < <(list_instances)
elif [ "$RUN_VM_INSTANCES" = "all" ]; then
  while IFS= read -r instance; do
    instances_to_test+=("$instance")
  done < <(list_instances)
else
  IFS=',' read -r -a instances_to_test <<< "${RUN_VM_INSTANCES}"
fi

if [ "${#instances_to_test[@]}" -eq 0 ]; then
  echo "no instances selected or discovered for VM integration test"
  exit 1
fi

for instance in "${instances_to_test[@]}"; do
  run_instance_test "$instance"
done
