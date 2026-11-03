#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils rustup gcc
# aka only. Does the simulation core build for WebAssembly as it is today?
set -euo pipefail
[[ $(hostname) == aka ]]
export RUSTUP_HOME="$HOME/eggshell-remote/rustup-wasm" CARGO_HOME="$HOME/eggshell-remote/cargo-wasm"
rustup toolchain install stable --profile minimal --target wasm32-unknown-unknown >/dev/null 2>&1
export CARGO_TARGET_DIR="$HOME/eggshell-remote/artifacts/full-rust-ab/speed/wasm-target"
rustup run stable cargo build --release --lib --target wasm32-unknown-unknown --manifest-path spikes/rust-stack/core/Cargo.toml 2>&1 | tail -5
ls -l "$CARGO_TARGET_DIR/wasm32-unknown-unknown/release/"*.rlib
printf 'CORE_WASM_BUILD_DONE\n'
