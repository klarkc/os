#!/usr/bin/env bash
# Execute as klarkc, never as root. Preserve an existing home; fail closed.
set -euo pipefail
if [[ "$(id -un)" != klarkc || "$HOME" != /home/klarkc ]]; then
  echo "Must run as klarkc with HOME=/home/klarkc" >&2
  exit 1
fi
cd "$HOME"
if [[ -e .git || -L .git ]]; then
  echo "Existing HOME Git metadata: manual inspection required" >&2
  exit 1
fi
stage="$(mktemp -d /tmp/solo-dotfiles.XXXXXXXX)"
trap 'rm -rf -- "$stage"' EXIT
git clone --depth 1 --branch main --no-checkout https://github.com/klarkc/dotfiles.git "$stage/repo"
# Never overwrite or silently move existing HOME files. Tracked paths,
# including dotfiles, must be unoccupied. Re-run only after manual review.
while IFS= read -r -d '' path; do
  if [[ -e "$HOME/$path" || -L "$HOME/$path" ]]; then
    printf 'Conflict: %q. Backup and resolve manually; no changes made.\n' "$path" >&2
    exit 1
  fi
done < <(git -C "$stage/repo" ls-tree -r -z --name-only HEAD)
# The repository itself must live at $HOME, not $HOME/dotfiles.
# Move Git metadata first and reset the index to materialize tracked files.
mv "$stage/repo/.git" "$HOME/.git"
if ! git read-tree --reset HEAD || ! git checkout-index --all; then
  echo "Checkout interrupted: inspect $HOME, do not run the script again blindly" >&2
  exit 1
fi
echo "Verified direct HOME checkout: $(git rev-parse HEAD)"
echo "Do NOT install .#default yet: it contains GPU/vLLM and Arch-specific tools."
echo "Prefer explicit CPU-only packages until a separate profile is reviewed."
