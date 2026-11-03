#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix git
# Time-boxed benchmark hint: essential load/120 idle-call checks only.
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
rust() { nix develop ./spikes/rust-stack/player -c "$@"; }
rust cargo fmt --manifest-path spikes/rust-stack/core/Cargo.toml
rust cargo fmt --manifest-path spikes/rust-stack/player/Cargo.toml
nix-shell spikes/rust-stack/tools/generate-scaling.py
ROOT="$HOME/eggshell-remote/artifacts/full-rust-ab/scaling"
SCHEMA="$HOME/eggshell-remote/artifacts/full-rust-ab/core/stride-4.7.2/schema.json"
for n in 25 50 100 200 400; do
  rust cargo run --manifest-path spikes/rust-stack/player/Cargo.toml -- --benchmark-host-check \
    "$ROOT/scale-$n.level.json" data/collision_table.json "$SCHEMA" 120
done
printf 'SCALING_HOST_CHECKS_DONE benchmark_unverified_level=true hint_only=true\n'
