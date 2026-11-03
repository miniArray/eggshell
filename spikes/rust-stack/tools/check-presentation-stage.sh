#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils git nix
set -euo pipefail
export NIX_CONFIG='builders ='
test "$(hostname)" = aka
nix config show | grep '^builders ='
OUT="$HOME/eggshell-remote/artifacts/full-rust-ab/player/presentation-stage"
mkdir -p "$OUT"
godot --headless --path . --script spikes/rust-stack/tools/export-view-metrics.gd -- "$OUT/view-metrics.json"
python3 spikes/rust-stack/tools/presentation-inspect.py
bash spikes/rust-stack/tools/check-player.sh
nix develop ./spikes/rust-stack/player -c cargo run --locked --manifest-path spikes/rust-stack/player/Cargo.toml -- --validate-assets \
  "$HOME/.local/share/eggshell-run/corpus/levels/6600ab52a3bb0805d316b9f1.json" \
  src/level/collision_table.json "$HOME/.local/share/eggshell/packs/original-v3-final" \
  "$HOME/eggshell-remote/player-pack-files.sha256.json" "$OUT/view-metrics.json" "$OUT/target-asset-bindings.json"
for fixture in stride bounce lagoon; do
  nix develop ./spikes/rust-stack/player -c cargo run --locked --manifest-path spikes/rust-stack/player/Cargo.toml -- --validate-assets \
    "tests/fixtures/$fixture.level.json" src/level/collision_table.json \
    "$HOME/.local/share/eggshell/packs/original-v3-final" "$HOME/eggshell-remote/player-pack-files.sha256.json" \
    "$OUT/view-metrics.json" "$OUT/$fixture-asset-bindings.json"
done
printf 'RUST_PRESENTATION_STAGE_DONE GPU_parity=not-tested target_gameplay=not-admitted artifact=%s\n' "$OUT"
