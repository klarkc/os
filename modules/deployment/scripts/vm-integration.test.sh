#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
if [ "${CI:-}" != "true" ]; then
  echo "VM integration test only runs in CI"
  exit 0
fi

echo "RUN_VM_INSTANCES=${RUN_VM_INSTANCES:-}"
echo "CI=${CI:-}"


if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "qemu not available; skipping VM integration test"
  exit 0
fi

if [ ! -e /dev/kvm ] || [ ! -w /dev/kvm ]; then
  echo "/dev/kvm not available or not writable; skipping VM integration test"
  exit 0
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

PORT="$(find_free_port)"
if [ -z "$PORT" ]; then
  echo "no free port available for VM SSH"
  exit 1
fi

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

EXTRA_MODULE="${TMP_DIR}/vm-extra.nix"
cat > "$EXTRA_MODULE" <<EOF
{ modulesPath, ... }: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/installer/scan/not-detected.nix")
  ];
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [ "${VM_SSH_PUB}" ];
  virtualisation.forwardPorts = [{
    from = "host";
    host.port = ${PORT};
    guest.port = 22;
  }];
  virtualisation.vmVariantWithDisko = {
    virtualisation.graphics = false;
  };
  virtualisation.memorySize = 2048;
  services.nginx.enable = false;
  services.nix-serve.enable = false;
  security.acme.acceptTerms = false;
}
EOF

find_instance_path() {
  local instance="$1"
  local -a matches=()
  while IFS= read -r match; do
    matches+=("$match")
  done < <(find "$REPO_ROOT/modules" -path "*/instances/${instance}.nix" -print)

  if [ "${#matches[@]}" -eq 0 ]; then
    echo "unknown instance: $instance"
    return 1
  fi

  if [ "${#matches[@]}" -gt 1 ]; then
    echo "ambiguous instance: $instance"
    printf '%s\n' "${matches[@]}"
    return 1
  fi

  printf '%s\n' "${matches[0]}"
}

run_instance_test() {
  local instance="$1"
  echo "Running VM integration test for instance: ${instance}"
  local instance_path
  instance_path="$(find_instance_path "$instance")"

  local shared_module disko_module
  shared_module="${REPO_ROOT}/modules/shared/system.nix"
  disko_module="${instance_path%.nix}.disko.nix"

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
{ lib, modulesPath, pkgs, ... }: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/installer/scan/not-detected.nix")
  ];
  environment.systemPackages = [ pkgs.rsync ];
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [ "${VM_SSH_PUB}" ];
  nix.settings.experimental-features = lib.mkForce [ "nix-command" "flakes" ];
  services.nginx.enable = false;
  services.nix-serve.enable = false;
  security.acme.acceptTerms = false;
}
EOF

  local flake_dir="${instance_tmp}/flake"
  mkdir -p "$flake_dir"

  cat > "${flake_dir}/flake.nix" <<EOF
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
        [ ${shared_module} ${instance_path} ${extra_module} ]
        ++ (if builtins.pathExists ${disko_module} then [
          disko.nixosModules.disko
          ${disko_module}
        ] else
          [ ]);
    in {
      nixosConfigurations."${instance}" = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = modules;
      };
    };
}
EOF

  if ! command -v nixos-rebuild >/dev/null 2>&1; then
    echo "nixos-rebuild not available; skipping VM integration test"
    return 0
  fi

  local out_link="${instance_tmp}/result"
  echo "nixos-rebuild build-vm --flake ${flake_dir}#${instance} --impure"
  (cd "$instance_tmp" && NIX_CONFIG="experimental-features = nix-command flakes" \
    nixos-rebuild build-vm --flake "${flake_dir}#${instance}" --impure)

  if [ ! -e "${out_link}/bin" ]; then
    echo "nixos-rebuild did not produce a VM build for ${instance}"
    return 1
  fi

  local vm_runner="${out_link}/bin/run-${instance}-vm"
  if [ ! -x "$vm_runner" ]; then
    vm_runner="$(find "${out_link}/bin" -maxdepth 1 -type f -name '*vm' | head -n 1 || true)"
  fi
  if [ -z "$vm_runner" ] || [ ! -x "$vm_runner" ]; then
    echo "vm runner not found for ${instance}"
    return 1
  fi

  echo "$vm_runner"
  QEMU_OPTS="-m 2048 -display none -serial mon:stdio -netdev user,id=net0,hostfwd=tcp::${port}-:22 -device virtio-net,netdev=net0" \
    "$vm_runner" &
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

  echo "ssh -p ${port} root@127.0.0.1 \"cd /root/os && ./modules/deployment/scripts/update-system.sh\""
  ssh "${SSH_OPTS[@]}" -p "$port" root@127.0.0.1 \
    "cd /root/os && ./modules/deployment/scripts/update-system.sh"

  echo "ssh -p ${port} root@127.0.0.1 \"systemctl poweroff\""
  ssh "${SSH_OPTS[@]}" -p "$port" root@127.0.0.1 "systemctl poweroff" || true

  VM_PID=""
  echo "vm integration test passed for ${instance}"
}

instances_to_test=()
if [ -z "${RUN_VM_INSTANCES:-}" ]; then
  echo "No instances selected; skipping VM integration test"
  exit 0
fi

if [ "$RUN_VM_INSTANCES" = "all" ]; then
  while IFS= read -r path; do
    instances_to_test+=("$(basename "$path" .nix)")
  done < <(find "$REPO_ROOT/modules" -path "*/instances/*.nix" ! -name "*.disko.nix" -print)
else
  IFS=',' read -r -a instances_to_test <<< "${RUN_VM_INSTANCES}"
fi

for instance in "${instances_to_test[@]}"; do
  run_instance_test "$instance"
done
