#!/usr/bin/env nix-shell
#! nix-shell -i bash -p cargo rustc rustfmt clippy
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
printf 'CORE_CHECK host=%s NIX_CONFIG=%s\n' "$(hostname)" "$NIX_CONFIG"
cargo fmt --manifest-path spikes/rust-stack/core/Cargo.toml
cargo test --manifest-path spikes/rust-stack/core/Cargo.toml
cargo clippy --manifest-path spikes/rust-stack/core/Cargo.toml --all-targets -- -D warnings
printf 'CORE_CHECK_DONE\n'
