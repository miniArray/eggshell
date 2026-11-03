#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
cargo fmt --manifest-path spikes/rust-stack/core/Cargo.toml
cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test target_next -- --ignored --nocapture
