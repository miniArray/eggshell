#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash nix ruff shellcheck
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
ruff check --select I --fix spikes/rust-stack/tools/summarize-real-cost.py
ruff format spikes/rust-stack/tools/summarize-real-cost.py
ruff check spikes/rust-stack/tools/summarize-real-cost.py
shellcheck --shell=bash spikes/rust-stack/tools/{check-real-cost,check-perf-host,profile-real-cost}.sh
rust() { nix develop ./spikes/rust-stack/player -c "$@"; }
rust cargo fmt --manifest-path spikes/rust-stack/core/Cargo.toml
rust cargo fmt --manifest-path spikes/rust-stack/player/Cargo.toml
rust cargo test --manifest-path spikes/rust-stack/player/Cargo.toml --lib --features benchmark-work-counters
rust cargo clippy --manifest-path spikes/rust-stack/player/Cargo.toml --features benchmark-work-counters --all-targets -- -D warnings
rust cargo check --manifest-path spikes/rust-stack/player/Cargo.toml
printf 'REAL_COST_FOCUSED_CHECK_DONE\n'
