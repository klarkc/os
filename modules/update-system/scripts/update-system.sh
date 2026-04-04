#!/usr/bin/env bash
set -euo pipefail

HOST="$1"

if [ -z "$HOST" ]; then
  echo "usage: update-system <host>"
  exit 1
fi

sudo rsync -a --delete ./ /etc/nixos/

sudo nixos-rebuild switch -I nixos-config=/etc/nixos/modules/$HOST/machine.nix
