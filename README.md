# os

[![Test](https://github.com/klarkc/os/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/klarkc/os/actions/workflows/test.yml?query=branch%3Amain)

Personal collection of NixOS machines.

## Deploying

### Cache

```bash
nixos-rebuild switch --flake .#cache-vultr --target-host "root@cache.tcp4.me"
```
