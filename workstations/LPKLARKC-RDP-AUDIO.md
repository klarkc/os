# RDP sound: lpklarkc client ↔ wsklarkc server

## Client

- FreeRDP forwards XRDP playback using `/sound:sys:alsa` on the existing IAP TCP RDP connection.
- Do not install a local PipeWire, PulseAudio, desktop manager, or extra streaming daemon.
- Defer `/microphone:sys:alsa` until device capture and server-side source work.
- Verify actual playback on Dell hardware. QEMU can test CLI wiring but not speaker output.

## BuildGCE contract

- Enable PipeWire and WirePlumber for the actual `klarkc` XRDP session.
- Package `neutrinolabs/pipewire-module-xrdp` reproducibly, pinned to revision/hash, compatible with deployed PipeWire.
- Load its XRDP modules in the user graphical session. Installing files alone is insufficient.
- Check virtual XRDP audio sink creation and playback through RDP; test mute, reconnect and server stop/start.
- Add microphone/source support as phase two, with a separate acceptance test.
- Use existing IAP TCP 3389; do not expose audio ports or create another VPN.
- Keep implementation on `feat/wsklarkc-gce`, not the BuildClient branch.

Upstream: https://github.com/neutrinolabs/pipewire-module-xrdp
XRDP: https://github.com/neutrinolabs/xrdp
