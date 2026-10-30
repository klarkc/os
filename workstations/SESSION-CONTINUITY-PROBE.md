# Session continuity probe: offline comparison and future GCE E2E

This tool **does not call Google Cloud APIs, suspend/resume a VM, create
accounts, restart services, install packages, or send notifications**.
`gce-session-continuity-probe.sh` reads an already-authenticated XRDP
session and produces narrowly scoped continuity evidence, never full
process environments, command lines, tokens or passwords.

## What counts as continuity

Capture and verification must run as root **on an explicitly approved,
equivalent disposable GCE VM** while the same real XRDP/XMonad user session
is present. The script checks:

- Same kernel `boot_id` (no reboot), same user's UID, exact XMonad PID,
  kernel process start ticks and Xorg `DISPLAY`.
- At least one pre-existing `tmux` server, with identical PID and start
  ticks; unrelated new tmux servers deliberately fail the comparison.
- An external test fixture saved in tmpfs, under `/run`, with identical
  SHA-256 before/after. A marker saved only in `HOME` is **not** evidence
  that guest RAM was preserved.
- Live per-user PipeWire/Pulse sockets, the virtual devices `xrdp-sink`
  and `xrdp-source`, and their selection as both audio defaults.

This is **necessary but insufficient**: also verify a protected active
agent/build PID, and real speaker playback and microphone capture on the
physical Dell after RDP reconnection. A visible sink/source alone does not
prove working bidirectional transport. No physical proof exists yet.

## Offline CI gate

```sh
bash -n workstations/scripts/gce-session-continuity-probe.sh
bash workstations/tests/test-gce-session-continuity-probe.sh
```

The tests are hermetic: they compare synthetic evidence, assert rejection of
changed XMonad start time, RAM marker, microphone, duplicate fields, missing
tmux and symlinked baselines. They **do not simulate GCE suspend**.

## Future authorized disposable-VM E2E recipe (not executed)

On a future approved test VM, create a RAM-only marker using a private
root-owned directory under `/run` and start a `tmux` server for the XRDP
user. Run `capture` inside the guest and save the output to a **trusted
external runner** before calling Compute Engine `instances.suspend`.
After the corresponding `instances.resume`, reconnect using the Dell's
IAP/FreeRDP path and run `verify` with that authenticated baseline:

```sh
sudo bash workstations/scripts/gce-session-continuity-probe.sh \
  capture wsklarkcci /run/wsklarkc-ci/ram-marker > before.evidence
# The separate authorized controller/test harness performs suspend/resume.
# On reconnection, send back the trusted before.evidence file:
sudo bash workstations/scripts/gce-session-continuity-probe.sh \
  verify wsklarkcci /run/wsklarkc-ci/ram-marker before.evidence
```

The test runner must ensure the baseline was actually captured **before**
suspension and is not generated from a second login. Both calls require an
existing XMonad and tmux session; the RAM marker must exist and be on a
tmpfs mount. The probe rejects missing/unknown state. Never use
`stop/start/reset/delete` as a fallback. A failed comparison is a NO-GO,
not a request to restart XMonad or delete processes.

No production operation is authorized by these commands or this document.
The canonical lifecycle contract remains in `klarkc/broker`.
