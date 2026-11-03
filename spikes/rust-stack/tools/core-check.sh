#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
# aka only. Fast compile check of the core: one line per error with its location.
set -euo pipefail
[[ $(hostname) == aka ]]
cargo check --locked --manifest-path spikes/rust-stack/core/Cargo.toml --lib --message-format short 2>&1 | grep -E 'error|warning: unused' | head -${1:-60} || true
printf 'CORE_CHECK_DONE\n'
