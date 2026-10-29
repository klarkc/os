# BuildGCE: bidirectional XRDP audio over IAP TCP

Only on `feat/wsklarkc-gce`. The Dell client (independent branch) uses `/sound:sys:pulse /microphone:sys:pulse`. Neither node exposes Dell hardware IDs; apps see `xrdp-sink` and `xrdp-source`.

## Reproducible server implementation

- Pinned upstream `neutrinolabs/pipewire-module-xrdp` at `a6e268b17093f8aab4e0fed9dcb23eaf87f7101c`, compiled against this flake's pinned PipeWire; a symlink union makes both upstream and XRDP module libraries available to the *per-user* PipeWire daemon.
- `services.pipewire` + WirePlumber + `pipewire-pulse` use the PAM-created `/run/user/<UID>` and user D-Bus. No PulseAudio daemon and no `services.xrdp.audio.enable`.
- XRDP's `startwm.sh` invokes `wsklarkc-xrdp-session`, checks `XRDP_SESSION`, `XRDP_SOCKET_PATH`, `XRDP_PULSE_SINK_SOCKET` and `XRDP_PULSE_SOURCE_SOCKET`, then loads one `pw-cli` module with both devices. It selects them as default sink/source, starts the HOME XMonad wrapper (or system XMonad), and retains the module through a disconnected session. Normal logout restores previous defaults and stops the module owner. Failures keep the desktop accessible but fail the audio E2E gate.
- No VPN, custom audio sockets on the VPC, RTP transport or extra firewall ingress. The only client RDP transport remains IAP TCP 3389.

## Validation tiers

1. **Nix eval + QEMU image:** assert user PipeWire, WirePlumber, module binary and wrapper presence. This does not prove XRDP login, audio delivery or input capture.
2. **Actual GCE authenticated FreeRDP E2E:** in `gce-rdp-guest-e2e.sh verify`, require user-owned XMonad process and both nodes/defaults via `pactl` on the *authenticated* user runtime. Repeat after actual stop/start. Current quota block prevents this until GCE VM exists.
3. **Dell physical acceptance (not substitutable by CI):** connect with FreeRDP sound+microphone; play a test WAV in remote XMonad and hear it on Dell speakers/headphones, record 5 seconds of microphone in GCE via `pw-record --target=xrdp-source` or `parecord --device=xrdp-source` and verify audible/nonzero samples, then repeat while muted/unmuted, with a USB headset swapped and after disconnect/reconnect/VM stop-start. Store separate timestamped playback and capture observations. Do not declare these completed without physical evidence.

On a *real authenticated* session, verify:

```sh
printf '%s\\n' "$XRDP_SESSION" "$XRDP_SOCKET_PATH" "$XRDP_PULSE_SINK_SOCKET" "$XRDP_PULSE_SOURCE_SOCKET"
systemctl --user is-active pipewire.service wireplumber.service pipewire-pulse.service
pactl list short sinks | grep xrdp-sink
pactl list short sources | grep xrdp-source
pactl get-default-sink
pactl get-default-source
```

Upstream: https://github.com/neutrinolabs/pipewire-module-xrdp and `instfiles/load_pw_modules.sh`. Avoid upstream's desktop autostart to prevent duplicate module instances under XMonad.
