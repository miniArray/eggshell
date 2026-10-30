#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix
# aka only. Print sample quads of tick 1, zoom 0 for one rebuilt real screen.
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
ROOT="$HOME/eggshell-remote/artifacts/full-rust-ab"
export CARGO_TARGET_DIR="$ROOT/speed/trace-target"
nix develop ./spikes/rust-stack/player -c cargo build --release --features benchmark-work-counters --manifest-path spikes/rust-stack/player/Cargo.toml
TRACE_DUMP_QUADS=1 "$CARGO_TARGET_DIR/release/eggshell-spike-player" --benchmark-trace-host "$ROOT/scaling/real-screens-v2/$1.level.json" \
  src/level/collision_table.json "$ROOT/core/stride-4.7.2/schema.json" 1 real-screen \
  "$HOME/.local/share/eggshell/packs/original-v3-final" "$HOME/eggshell-remote/player-pack-files.sha256.json" \
  "$ROOT/player/presentation-stage/view-metrics.json" | grep QUAD
