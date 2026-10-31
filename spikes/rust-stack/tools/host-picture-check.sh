#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix
# aka only. Usage: host-picture-check.sh LEVEL_JSON [TICKS]
# Loads an unchanged level, prepares its scene from the private pack, and builds the
# picture at every zoom for TICKS idle steps (no GPU). Fails on any refusal or missing art.
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
ROOT="$HOME/eggshell-remote/artifacts/full-rust-ab"
export CARGO_TARGET_DIR="$ROOT/speed/trace-target"
nix develop ./spikes/rust-stack/player -c cargo build --release --features benchmark-work-counters --manifest-path spikes/rust-stack/player/Cargo.toml 2>&1 | tail -2
"$CARGO_TARGET_DIR/release/eggshell-spike-player" --benchmark-trace-host "$1" src/level/collision_table.json \
  "$ROOT/core/stride-4.7.2/schema.json" "${2:-600}" synthetic \
  "$HOME/.local/share/eggshell/packs/original-v3-final" "$HOME/eggshell-remote/player-pack-files.sha256.json" \
  "$ROOT/player/presentation-stage/view-metrics.json"
printf 'HOST_PICTURE_CHECK_DONE level=%s\n' "$1"
