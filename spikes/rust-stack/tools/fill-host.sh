#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils
# aka only, in the player dev shell. Usage: fill-host.sh TICK LEVEL_ID...
# Prints HOST_FILL (screen fill by image) for each corpus level after TICK route steps.
set -euo pipefail
[[ $(hostname) == aka ]]
tick=$1
shift
for id in "$@"; do
  cargo run --quiet --locked --release --manifest-path spikes/rust-stack/player/Cargo.toml -- --fill-host \
    "$HOME/.local/share/eggshell-run/corpus/levels/$id.json" data/collision_table.json \
    "$HOME/eggshell-remote/artifacts/full-rust-ab/core/stride-4.7.2/schema.json" \
    "$HOME/.local/share/eggshell/packs/original-v3-final" "$HOME/eggshell-remote/player-pack-files.sha256.json" \
    "$HOME/eggshell-remote/artifacts/full-rust-ab/player/presentation-stage/view-metrics.json" "$tick" || echo "HOST_FILL_FAILED $id"
done
