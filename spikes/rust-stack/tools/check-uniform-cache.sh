#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash nix
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
nix develop ./spikes/rust-stack/player -c cargo fmt --manifest-path spikes/rust-stack/player/Cargo.toml
nix develop ./spikes/rust-stack/player -c cargo test --manifest-path spikes/rust-stack/player/Cargo.toml --lib
nix develop ./spikes/rust-stack/player -c cargo clippy --manifest-path spikes/rust-stack/player/Cargo.toml --lib -- -D warnings
printf 'UNIFORM_CACHE_CHECK_DONE benchmark_only=true\n'
