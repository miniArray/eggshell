#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils
# aka only, inside the player dev shell. Usage: level-index.sh OUT.json
# Writes the level list index of the private corpus for this build (--level-index).
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
OUT=$1
cargo run --quiet --locked --release --manifest-path spikes/rust-stack/player/Cargo.toml -- --level-index \
  "${PLAYER_LEVELS_DIR:-$HOME/.local/share/eggshell-run/corpus/levels}" src/level/collision_table.json \
  "$HOME/eggshell-remote/artifacts/full-rust-ab/core/stride-4.7.2/schema.json" \
  "$HOME/.local/share/eggshell/packs/original-v3-final" "$HOME/eggshell-remote/player-pack-files.sha256.json" \
  "$HOME/eggshell-remote/artifacts/full-rust-ab/player/presentation-stage/view-metrics.json" "$OUT" |
  grep -v '^LEVEL_INDEX_ENTRY .* ok=true' | grep -E 'LEVEL_INDEX_DONE|LEVEL_INDEX_ENTRY' | tail -n 400 > "$OUT.log"
grep LEVEL_INDEX_DONE "$OUT.log"
