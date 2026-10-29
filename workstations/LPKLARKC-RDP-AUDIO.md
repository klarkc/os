# lpklarkc ↔ wsklarkc: bidirectional RDP audio

## User experience

- Dell speakers/headphones play workstation application sound.
- Dell integrated/USB/headset microphone is available to workstation applications.
- The workstation sees XRDP virtual sink/source nodes; *not* the exact Dell
  ALSA hardware card IDs. Apps can select the virtual microphone and sink as
  standard PipeWire audio devices. No manual address or socket setup.
- The audio is transported over the existing IAP-forwarded RDP connection
  on TCP 3389. There are no separate audio ports or VPN connections.

## BuildClient (`feat/lpklarkc-ci-20261029`)

- Enable PipeWire, WirePlumber, ALSA support and `pipewire-pulse`.
- FreeRDP 3 uses `/sound:sys:pulse /microphone:sys:pulse`: the `pulse`
  backend speaks the PulseAudio **protocol** to PipeWire; it does not
  require the original PulseAudio daemon.
- Keep the generic graphical desktop, XFCE, LightDM, Openbox and Xterm off.
- Preserve hardware audio kernel drivers and validate Dell speakers,
  internal microphone, USB/headset devices and hotplug on physical hardware.
- CI: evaluate the PipeWire service stack, inspect both FreeRDP arguments
  and prove user PulseAudio-compatible socket and PipeWire core in QEMU.
  The VM cannot prove a physical speaker/microphone or GCE audio stream.
- If size budget fails, measure the *built ISO* before deciding new cap.

## BuildGCE (`feat/wsklarkc-gce`), independent branch

- PipeWire + WirePlumber must run under `klarkc`'s **actual XRDP login
  session**, with its correct user bus, DISPLAY and XDG_RUNTIME_DIR.
- Package and pin `neutrinolabs/pipewire-module-xrdp` as a Nix derivation
  compatible with the server PipeWire version. Ensure its session loader
  starts both `xrdp-sink` and `xrdp-source` (see upstream
  `instfiles/load_pw_modules.sh`) at every RDP login/reconnect.
- Ensure xrdp-sink is the default playback sink, and xrdp-source the
  default recording source *for this XRDP session*; preserve unrelated
  desktop/audio routing.
- NixOS `services.xrdp.audio.enable` currently supports a legacy
  PulseAudio XRDP module, **not** the PipeWire XRDP module. Implement
  PipeWire integration directly rather than setting that switch.
- Test module loading, virtual source/sink, sound from server to Dell,
  and microphone recording in server from Dell to server. Test reconnect,
  mic mute and replacement USB headset, with explicit E2E evidence.
- Never expose PipeWire sockets or audio ports externally; IAP 3389 only.

## References

- https://github.com/neutrinolabs/pipewire-module-xrdp
- https://github.com/neutrinolabs/pipewire-module-xrdp/blob/devel/instfiles/load_pw_modules.sh
- https://github.com/FreeRDP/FreeRDP
- https://wiki.nixos.org/wiki/PipeWire
