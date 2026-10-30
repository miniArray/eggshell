#!/usr/bin/env nix-shell
#! nix-shell toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
printf 'CORE_CHECK host=%s NIX_CONFIG=%s\n' "$(hostname)" "$NIX_CONFIG"
rustc --version --verbose
cargo --version
printf 'LOCKED_NIXPKGS='
python3 -c 'import json; print(json.load(open("flake.lock"))["nodes"]["nixpkgs"]["locked"]["rev"])'
cargo fmt --manifest-path spikes/rust-stack/core/Cargo.toml
cargo test --manifest-path spikes/rust-stack/core/Cargo.toml
cargo clippy --manifest-path spikes/rust-stack/core/Cargo.toml --all-targets -- -D warnings
printf 'CORE_CHECK_DONE\n'
