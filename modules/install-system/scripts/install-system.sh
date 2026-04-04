#!/usr/bin/env bash
set -euo pipefail

HOST="$1"

if [ -z "$HOST" ]; then
  echo "usage: install-system <host>"
  exit 1
fi

if [ ! -d "./modules/$HOST" ]; then
  echo "unknown host: $HOST"
  exit 1
fi

if [ -f "./modules/$HOST/disko.nix" ]; then
  sudo disko --mode destroy,format,mount ./modules/$HOST/disko.nix
fi

sudo mkdir -p /mnt/etc/nixos
sudo rsync -a --delete ./ /mnt/etc/nixos/

sudo nixos-install -I nixos-config=/mnt/etc/nixos/modules/$HOST/machine.nix
