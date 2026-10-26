#!/usr/bin/env bash
# Run as the unprivileged klarkc account, after VM provisioning.
# Conservative: refuses to overwrite an already populated home checkout.
set -euo pipefail
if [[ "${USER:-}" != "klarkc" ]]; then
  echo "Run as the klarkc account" >&2
  exit 1
fi
cd "$HOME"
if [[ -d .git ]]; then
  echo "Home already has a Git checkout: inspect before making changes."
  git status --short
  exit 0
fi
echo "Backing up conflicting default profile files, if present."
mkdir -p "$HOME/.pre-dotfiles-bootstrap"
for name in .bashrc .profile .bash_profile .bash_logout; do
  if [[ -e "$HOME/$name" ]]; then
    mv "$HOME/$name" "$HOME/.pre-dotfiles-bootstrap/$name"
  fi
done
git init -b main
git remote add origin https://github.com/klarkc/dotfiles.git
git fetch --depth 1 origin main
git checkout -B main FETCH_HEAD
echo "Dotfiles are now checked out DIRECTLY at HOME."
echo "Run: nix profile install .#default"
echo "NVIDIA-specific profile outputs in dotfiles may require a CPU-only update."
echo "Do not run 'make' until the Arch-specific assumptions are reviewed."
