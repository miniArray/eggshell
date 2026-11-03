#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix shellcheck
# aka only. Atlas unit tests, player tests, lints and a release build.
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
rust() { nix develop ./spikes/rust-stack/player -c "$@"; }
rust cargo fmt --manifest-path spikes/rust-stack/player/Cargo.toml
shellcheck --shell=bash spikes/rust-stack/tools/check-atlas.sh spikes/rust-stack/tools/launch-owned-stress.sh
rust cargo test --manifest-path spikes/rust-stack/player/Cargo.toml --lib atlas -- --nocapture
rust cargo test --manifest-path spikes/rust-stack/player/Cargo.toml --lib --features benchmark-work-counters
rust cargo clippy --manifest-path spikes/rust-stack/player/Cargo.toml --features benchmark-work-counters --all-targets -- -D warnings
rust cargo clippy --manifest-path spikes/rust-stack/player/Cargo.toml --all-targets -- -D warnings
rust cargo build --release --manifest-path spikes/rust-stack/player/Cargo.toml
echo ATLAS_CHECK_DONE
