#!/usr/bin/env bash
# Hermetic comparator tests. No cloud, xrdp, sudo or /proc access required.
set -euo pipefail
script="$(cd -- "$(dirname -- "$0")/../scripts" && pwd)/gce-session-continuity-probe.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
cat >"$tmp/before" <<'STATE'
boot_id=123e4567-e89b-12d3-a456-426614174000
uid=1001
xmonad_pid=678
xmonad_start_ticks=910000
display=:10
ram_sha256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
sink=xrdp-sink
source=xrdp-source
tmux=700:910005
STATE
cp "$tmp/before" "$tmp/after"
bash "$script" compare "$tmp/before" "$tmp/after" >/dev/null
sed -i 's/xmonad_start_ticks=910000/xmonad_start_ticks=910001/' "$tmp/after"
if bash "$script" compare "$tmp/before" "$tmp/after" >/dev/null 2>&1; then echo 'FAIL: changed process identity accepted' >&2; exit 1; fi
cp "$tmp/before" "$tmp/after"
sed -i 's/ram_sha256=0123/ram_sha256=ffff/' "$tmp/after"
if bash "$script" compare "$tmp/before" "$tmp/after" >/dev/null 2>&1; then echo 'FAIL: changed RAM marker accepted' >&2; exit 1; fi
cp "$tmp/before" "$tmp/after"
sed -i 's/source=xrdp-source/source=system-microphone/' "$tmp/after"
if bash "$script" compare "$tmp/before" "$tmp/after" >/dev/null 2>&1; then echo 'FAIL: changed source accepted' >&2; exit 1; fi
cp "$tmp/before" "$tmp/after"
printf 'source=xrdp-source\n' >>"$tmp/after"
if bash "$script" compare "$tmp/before" "$tmp/after" >/dev/null 2>&1; then echo 'FAIL: duplicate key accepted' >&2; exit 1; fi
cp "$tmp/before" "$tmp/after"
sed -i '/^tmux=/d' "$tmp/after"
if bash "$script" compare "$tmp/before" "$tmp/after" >/dev/null 2>&1; then echo 'FAIL: missing tmux accepted' >&2; exit 1; fi
ln -s "$tmp/before" "$tmp/link"
if bash "$script" compare "$tmp/link" "$tmp/before" >/dev/null 2>&1; then echo 'FAIL: symlink accepted' >&2; exit 1; fi
if bash "$script" capture dummy /run/marker >/dev/null 2>&1; then echo 'FAIL: unprivileged/no XRDP capture accepted' >&2; exit 1; fi
echo 'PASS: 7 offline continuity comparator scenarios'
