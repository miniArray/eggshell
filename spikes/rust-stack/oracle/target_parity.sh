#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
# aka only. Record Godot on the unchanged 204-object target with the normal-input
# exploration route (oracle/target_route.py), then require Rust to match every tick.
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
nix-shell spikes/rust-stack/oracle/run.sh target
cargo test --locked --release --manifest-path spikes/rust-stack/core/Cargo.toml --test target_next -- --ignored --nocapture
printf 'TARGET_PARITY_DONE source=%s\n' "$(git rev-parse HEAD)"
