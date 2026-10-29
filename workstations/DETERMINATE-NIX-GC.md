# Determinate Nix and weekly GC on wsklarkc

Official NixOS module pinned to Determinate v3.24.1 in `flake.lock`,
imported only for the GCE workstation and its QEMU tests.

## Exactly one automatic garbage collector

Determinate Nixd's automatic collector is disabled through
`/etc/determinate/config.json` (`garbageCollector.strategy=disabled`).
NixOS owns the weekly `nix-gc.timer` (Sunday 03:35 America/Bahia, 30m
random delay and persistent catch-up).
`nix-collect-garbage --delete-older-than 30d` prunes old generations
while preserving currently referenced system/user profiles and store
roots. The service runs with low CPU and I/O scheduling priority.

Protect important custom build outputs with a durable Nix GC root.
Never remove active roots or profiles to free disk, or treat GC as a backup.

Read-only checks after boot:
```sh
systemctl list-timers nix-gc.timer
systemctl cat nix-daemon.service
cat /etc/determinate/config.json
journalctl -u nix-gc.service --since '30 days ago'
nix-store --gc --print-roots
nix-store --gc --print-dead
df -h /nix
```

CI evaluates the GC policy and checks the daemon/timer in QEMU.
A real disk-pressure test is still pending an explicitly approved
disposable VM. It must preserve live roots, running jobs and user data.
Do not activate paid GCE deploy or automatic suspend without approval.

Official instructions: https://docs.determinate.systems/guides/advanced-installation/
GC configuration: https://docs.determinate.systems/determinate-nix/determinate-nixd/
