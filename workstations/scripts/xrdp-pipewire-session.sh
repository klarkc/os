#!/usr/bin/env bash
# Called exclusively by XRDP's startwm.sh, AFTER PAM opened a user session.
# No separate network audio transport, daemon-wide XRDP environment or legacy
# PulseAudio server is involved. One module owner per graphical login.
set -euo pipefail

if [[ -x "$HOME/.local/bin/xmonad-session" ]]; then
  wm=( "$HOME/.local/bin/xmonad-session" )
else
  wm=( xmonad )
fi

# Never make the desktop itself inaccessible if the audio side is broken:
# a real RDP/CI audio probe will fail separately with diagnostic evidence.
without_audio() {
  echo "XRDP_AUDIO_DEGRADED: $1" >&2
  exec "${wm[@]}"
}

for variable in XRDP_SESSION XRDP_SOCKET_PATH XRDP_PULSE_SINK_SOCKET XRDP_PULSE_SOURCE_SOCKET; do
  if [[ -z "${!variable:-}" ]]; then
    without_audio "missing XRDP session variable: $variable"
  fi
done

uid="$(id -u)"
expected_runtime="/run/user/$uid"
if [[ -n "${XDG_RUNTIME_DIR:-}" && "$XDG_RUNTIME_DIR" != "$expected_runtime" ]]; then
  without_audio "unexpected XDG_RUNTIME_DIR; refusing cross-user audio"
fi
export XDG_RUNTIME_DIR="$expected_runtime"
if [[ ! -d "$XDG_RUNTIME_DIR" || ! -O "$XDG_RUNTIME_DIR" || ! -S "$XDG_RUNTIME_DIR/bus" ]]; then
  without_audio "XRDP PAM/systemd user runtime or D-Bus socket unavailable"
fi
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
export PULSE_SERVER="unix:$XDG_RUNTIME_DIR/pulse/native"

if ! systemctl --user start pipewire.socket pipewire-pulse.socket wireplumber.service; then
  without_audio "failed to start user PipeWire/WirePlumber"
fi

ready=0
for _attempt in $(seq 1 40); do
  if pactl info >/dev/null 2>&1 && pw-cli quit >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.25
done
[[ "$ready" == 1 ]] || without_audio "user PipeWire/pipewire-pulse never became ready"

previous_sink="$(pactl get-default-sink 2>/dev/null || true)"
previous_source="$(pactl get-default-source 2>/dev/null || true)"
module_pid=""
wm_pid=""

has_sink() {
  pactl list short sinks | awk '$2 == "xrdp-sink" { found=1 } END { exit !found }'
}
has_source() {
  pactl list short sources | awk '$2 == "xrdp-source" { found=1 } END { exit !found }'
}
restore_defaults() {
  if [[ -n "$previous_sink" && "$previous_sink" != xrdp-sink ]] &&
    pactl list short sinks | awk -v name="$previous_sink" '$2 == name { found=1 } END { exit !found }'; then
    pactl set-default-sink "$previous_sink" || true
  fi
  if [[ -n "$previous_source" && "$previous_source" != xrdp-source ]] &&
    pactl list short sources | awk -v name="$previous_source" '$2 == name { found=1 } END { exit !found }'; then
    pactl set-default-source "$previous_source" || true
  fi
}
cleanup() {
  restore_defaults
  if [[ -n "$module_pid" ]]; then
    kill "$module_pid" >/dev/null 2>&1 || true
    wait "$module_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
trap 'exit 129' HUP

# Loading in the user's session, rather than pipewire.service, is crucial:
# the module reads all XRDP socket paths from its load-time environment.
# Keep the pw-cli module owner alive until this XMonad session exits.
pw-cli -m -d load-module libpipewire-module-xrdp \
  'sink.node.latency=2048' \
  'sink.stream.props={node.name=xrdp-sink}' \
  'source.stream.props={node.name=xrdp-source}' >/dev/null 2>&1 &
module_pid=$!

ready=0
for _attempt in $(seq 1 60); do
  if ! kill -0 "$module_pid" 2>/dev/null; then break; fi
  if has_sink && has_source; then
    ready=1
    break
  fi
  sleep 0.25
done
if [[ "$ready" == 1 ]] &&
  pactl set-default-sink xrdp-sink &&
  pactl set-default-source xrdp-source &&
  [[ "$(pactl get-default-sink)" == xrdp-sink ]] &&
  [[ "$(pactl get-default-source)" == xrdp-source ]]; then
  echo "XRDP_AUDIO_READY: xrdp-sink (playback) + xrdp-source (microphone)" >&2
else
  echo "XRDP_AUDIO_DEGRADED: module failed to expose both virtual devices/defaults" >&2
fi

# Keep the wrapper and module owner alive on a disconnected-but-retained
# session; XRDP reconnects to that same XMonad process and chansrv sockets.
# A terminated session triggers trap cleanup so the next login is clean.
"${wm[@]}" &
wm_pid=$!
set +e
wait "$wm_pid"
wm_status=$?
set -e
exit "$wm_status"
