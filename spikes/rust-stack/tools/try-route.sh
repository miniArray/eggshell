#!/usr/bin/env bash
# aka only, in the player dev shell. Usage: try-route.sh LEVEL ROUTE.json
# Prints HELD_TRACE_PLAYER (Yoshi position, carried eggs, health, visible Snifit shots)
# for every call of a replayed route on LEVEL.
set -euo pipefail
C="$HOME/eggshell-remote/artifacts/full-rust-ab/core"
HELD_TRACE_PLAYER=1 cargo run --quiet --release --manifest-path spikes/rust-stack/player/Cargo.toml -- --held-trace \
  "$1" data/collision_table.json "$C/stride-4.7.2/schema.json" \
  "$HOME/.local/share/eggshell/packs/original-v3-final" "$HOME/eggshell-remote/player-pack-files.sha256.json" \
  "$HOME/eggshell-remote/artifacts/full-rust-ab/player/presentation-stage/view-metrics.json" "$2" 2>&1 | grep '^HELD_TRACE_PLAYER'
