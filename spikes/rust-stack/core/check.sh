#!/usr/bin/env nix-shell
#! nix-shell toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
if [[ -n "${EXPECTED_SOURCE_SHA:-}" ]]; then
  test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_SHA"
fi
printf 'CORE_CHECK host=%s NIX_CONFIG=%s\n' "$(hostname)" "$NIX_CONFIG"
rustc --version --verbose
cargo --version
printf 'LOCKED_NIXPKGS='
python3 -c 'import json; print(json.load(open("flake.lock"))["nodes"]["nixpkgs"]["locked"]["rev"])'
cargo fmt --manifest-path spikes/rust-stack/core/Cargo.toml
cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml
if [[ -n "${CORE_ORACLE_DIR:-}" ]]; then
  export HOSTNAME=aka
  cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test oracle_codec -- --ignored --nocapture
fi
if [[ -n "${CORE_PROOF_DIR:-}" ]]; then
  cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test oracle_foundations -- --ignored --nocapture
fi
if [[ "${CORE_STRIDE:-0}" == 1 ]]; then
  cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test stride_session --test stride_uninterrupted --test stride_overflow -- --ignored --nocapture
fi
cargo clippy --locked --manifest-path spikes/rust-stack/core/Cargo.toml --all-targets -- -D warnings
printf 'CORE_CHECK_DONE\n'
printf 'CORE_API_READY source=%s rotation_degrees=Option-f64 auxiliary=PlantHead scope=Stride-only target=refused\n' "$(git rev-parse HEAD)"
