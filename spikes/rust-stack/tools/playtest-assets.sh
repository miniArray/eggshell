#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix
# aka only. Private art report for the playtest level(s), including runtime-created codes.
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
ROOT="$HOME/eggshell-remote/artifacts/full-rust-ab"
nix develop ./spikes/rust-stack/player -c cargo run --release --manifest-path spikes/rust-stack/player/Cargo.toml -- --validate-assets \
  "$HOME/.local/share/eggshell-run/corpus/levels/6600ab52a3bb0805d316b9f1.json" data/collision_table.json \
  "$HOME/.local/share/eggshell/packs/original-v3-final" "$HOME/eggshell-remote/player-pack-files.sha256.json" \
  "$ROOT/player/presentation-stage/view-metrics.json" "$ROOT/player/playtest-assets.json"
printf 'PLAYTEST_ASSETS_DONE\n'
