#!/usr/bin/env bash
# Evidence-only probe: NO cloud calls, no service changes and no writes to VM.
# Full E2E still requires real GCE suspend/resume and physical two-way audio.
set -euo pipefail
umask 077

usage() {
  echo 'Usage: probe.sh capture USER /run/TMPFS/MARKER | verify USER /run/TMPFS/MARKER BASELINE | compare BEFORE AFTER' >&2
  exit 2
}

process_start_ticks() {
  local pid="$1"
  [[ "$pid" =~ ^[1-9][0-9]*$ && -r "/proc/$pid/stat" ]] || return 1
  # Remove the parenthesized comm field (which may itself contain spaces).
  sed 's/^.*) //' "/proc/$pid/stat" | awk '{print $20}'
}

pactl_as_user() {
  runuser -u "$probe_user" -- env \
    XDG_RUNTIME_DIR="$runtime" \
    PULSE_SERVER="unix:$runtime/pulse/native" \
    pactl "$@"
}

capture() {
  local display ram_hash pid tmux_count=0
  [[ "$#" -eq 2 && "$(id -u)" -eq 0 ]] || usage
  probe_user="$1"
  marker="$2"
  [[ "$probe_user" =~ ^[a-z_][a-z_0-9-]*$ ]] || usage
  [[ "$marker" == /run/* && -f "$marker" && ! -L "$marker" && -r "$marker" ]] || {
    echo 'FAIL: marker must be a readable regular file under /run' >&2
    return 1
  }
  [[ "$(stat -f -c %T -- "$marker")" == tmpfs ]] || {
    echo 'FAIL: marker is not backed by tmpfs/RAM' >&2
    return 1
  }
  uid="$(id -u "$probe_user")"
  runtime="/run/user/$uid"
  [[ -S "$runtime/pipewire-0" && -S "$runtime/pulse/native" ]] || {
    echo 'FAIL: per-user PipeWire and Pulse sockets are not ready' >&2
    return 1
  }
  mapfile -t xmonads < <(pgrep -u "$probe_user" -x xmonad || true)
  [[ "${#xmonads[@]}" -eq 1 ]] || {
    echo 'FAIL: expected exactly one original XMonad process' >&2
    return 1
  }
  pid="${xmonads[0]}"
  display="$(tr '\0' '\n' <"/proc/$pid/environ" | sed -n 's/^DISPLAY=//p' | head -n 1)"
  [[ "$display" =~ ^:[0-9]+(\.[0-9]+)?$ ]] || {
    echo 'FAIL: original XMonad has no valid XRDP DISPLAY' >&2
    return 1
  }
  pactl_as_user list short sinks | awk '$2 == "xrdp-sink" { ok=1 } END { exit !ok }' || {
    echo 'FAIL: xrdp-sink missing after reconnect' >&2
    return 1
  }
  pactl_as_user list short sources | awk '$2 == "xrdp-source" { ok=1 } END { exit !ok }' || {
    echo 'FAIL: xrdp-source missing after reconnect' >&2
    return 1
  }
  [[ "$(pactl_as_user get-default-sink)" == xrdp-sink && \
     "$(pactl_as_user get-default-source)" == xrdp-source ]] || {
    echo 'FAIL: XRDP virtual sink/source not selected as defaults' >&2
    return 1
  }
  ram_hash="$(sha256sum -- "$marker" | awk '{print $1}')"
  printf 'boot_id=%s\n' "$(cat /proc/sys/kernel/random/boot_id)"
  printf 'uid=%s\n' "$uid"
  printf 'xmonad_pid=%s\n' "$pid"
  xmonad_ticks="$(process_start_ticks "$pid")" || { echo 'FAIL: XMonad exited during probe' >&2; return 1; }
  printf 'xmonad_start_ticks=%s\n' "$xmonad_ticks"
  printf 'display=%s\n' "$display"
  printf 'ram_sha256=%s\n' "$ram_hash"
  printf 'sink=xrdp-sink\nsource=xrdp-source\n'
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    tmux_ticks="$(process_start_ticks "$pid")" || { echo 'FAIL: tmux exited during probe' >&2; return 1; }
    printf 'tmux=%s:%s\n' "$pid" "$tmux_ticks"
    tmux_count=$((tmux_count + 1))
  done < <(pgrep -u "$probe_user" -x tmux | sort -n || true)
  [[ "$tmux_count" -gt 0 ]] || {
    echo 'FAIL: no live tmux process to prove continuity' >&2
    return 1
  }
}

validate_file() {
  local file="$1"
  [[ -f "$file" && ! -L "$file" && -s "$file" ]] || return 1
  awk -F= '
    BEGIN {
      n=split("boot_id uid xmonad_pid xmonad_start_ticks display ram_sha256 sink source", keys, " ");
      for (i = 1; i <= n; i++) required[keys[i]] = 1
    }
    NF != 2 { bad=1; next }
    $1 == "tmux" {
      if ($2 !~ /^[1-9][0-9]*:[1-9][0-9]*$/) bad=1;
      tmux_count++;
      next
    }
    !($1 in required) || seen[$1]++ { bad=1; next }
    $1 == "boot_id" && ($2 !~ /^[0-9a-f-]+$/ || length($2) != 36) { bad=1 }
    $1 == "uid" && $2 !~ /^[0-9]+$/ { bad=1 }
    ($1 == "xmonad_pid" || $1 == "xmonad_start_ticks") && $2 !~ /^[1-9][0-9]*$/ { bad=1 }
    $1 == "display" && $2 !~ /^:[0-9]+(\.[0-9]+)?$/ { bad=1 }
    $1 == "ram_sha256" && ($2 !~ /^[0-9a-f]+$/ || length($2) != 64) { bad=1 }
    $1 == "sink" && $2 != "xrdp-sink" { bad=1 }
    $1 == "source" && $2 != "xrdp-source" { bad=1 }
    END {
      for (key in required) if (seen[key] != 1) bad=1;
      if (tmux_count < 1 || bad) exit 1
    }
  ' "$file"
}

compare() {
  [[ "$#" -eq 2 ]] || usage
  validate_file "$1" && validate_file "$2" || {
    echo 'FAIL: missing or malformed continuity evidence' >&2
    return 1
  }
  if ! cmp -s -- "$1" "$2"; then
    echo 'FAIL: boot, RAM marker, XMonad, tmux or XRDP audio identity changed' >&2
    diff -u -- "$1" "$2" >&2 || true
    return 1
  fi
  echo 'PASS: continuity evidence matches (physical audio still untested)' >&2
}

case "${1:-}" in
  capture)
    [[ "$#" -eq 3 ]] || usage
    capture "$2" "$3"
    ;;
  verify)
    [[ "$#" -eq 4 ]] || usage
    baseline="$4"
    tmp="$(mktemp)"
    trap 'rm -f -- "$tmp"' EXIT
    capture "$2" "$3" >"$tmp"
    compare "$baseline" "$tmp"
    ;;
  compare)
    [[ "$#" -eq 3 ]] || usage
    compare "$2" "$3"
    ;;
  *) usage ;;
esac
