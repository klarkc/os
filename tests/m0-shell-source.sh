#!/usr/bin/env bash
# Synthetic native Shell source for M0: author/edit here, execute the Nix output.
set -euo pipefail
printf 'nix-m0-materialized:%s\n' "${1:-default}"
