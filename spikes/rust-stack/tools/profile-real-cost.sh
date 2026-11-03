#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix linuxPackages.perf python3
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
ROOT="$HOME/eggshell-remote/artifacts/full-rust-ab"
D="$ROOT/speed/diag-real-cost-$(date -u +%Y%m%dT%H%M%S)-$$"
mkdir "$D"
git rev-parse HEAD > "$D/source-sha.txt"
printf 'DIAG_ARTIFACT=%s\n' "$D"
rust() { nix develop ./spikes/rust-stack/player -c "$@"; }
export RUSTFLAGS='-C force-frame-pointers=yes -C debuginfo=2'
export CARGO_TARGET_DIR="$D/target"
rust cargo build --release --manifest-path spikes/rust-stack/player/Cargo.toml
cp "$CARGO_TARGET_DIR/release/eggshell-spike-player" "$D/profile-player"
BIN="$D/profile-player"
SCHEMA="$ROOT/core/stride-4.7.2/schema.json"
for name in real-64d3d5f1d77b3fe14198c693 real-6aa65f0c574012395a0faddf scale-2400; do
  if [[ "$name" == real-* ]]; then level="$ROOT/scaling/real-screens-v2/$name.level.json"; mode=real-screen; else level="$ROOT/scaling/$name.level.json"; mode=synthetic; fi
  perf record -e cpu-clock:u -F 4999 --call-graph fp -o "$D/$name.perf.data" -- \
    "$BIN" --benchmark-profile-host "$level" data/collision_table.json "$SCHEMA" 300 "$mode" | tee "$D/$name.profile.txt"
  perf script -i "$D/$name.perf.data" > "$D/$name.perf.script.txt"
  perf report -i "$D/$name.perf.data" --stdio --children > "$D/$name.perf.report.txt"
done
# A separate feature-enabled executable: row and scene counters do not pollute profiles.
rust cargo build --release --features benchmark-work-counters --manifest-path spikes/rust-stack/player/Cargo.toml
cp "$CARGO_TARGET_DIR/release/eggshell-spike-player" "$D/work-player"
BIN="$D/work-player"
for name in real-64d3d5f1d77b3fe14198c693 real-6aa65f0c574012395a0faddf scale-2400; do
  if [[ "$name" == real-* ]]; then level="$ROOT/scaling/real-screens-v2/$name.level.json"; mode=real-screen; original="$HOME/.local/share/eggshell-run/corpus/levels/${name#real-}.json"; else level="$ROOT/scaling/$name.level.json"; mode=synthetic; original=-; fi
  "$BIN" --benchmark-work-host "$level" data/collision_table.json "$SCHEMA" 300 "$mode" "$original" \
    "$HOME/.local/share/eggshell/packs/original-v3-final" "$HOME/eggshell-remote/player-pack-files.sha256.json" \
    "$ROOT/player/presentation-stage/view-metrics.json" "$D/$name.work.json"
done
python3 spikes/rust-stack/tools/summarize-real-cost.py "$D"
printf 'REAL_COST_DIAGNOSIS_DONE artifact=%s\n' "$D"
