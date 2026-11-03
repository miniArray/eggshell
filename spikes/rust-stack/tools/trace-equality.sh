#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix diffutils
# aka only. Usage: trace-equality.sh TAG [BASELINE_TAG]
# Writes speed/trace-TAG.txt (per-50-tick chained digests of presentation, snapshot
# and scene quads); with BASELINE_TAG, fails unless both traces are identical.
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
TAG=$1
ROOT="$HOME/eggshell-remote/artifacts/full-rust-ab"
OUT="$ROOT/speed/trace-$TAG.txt"
export CARGO_TARGET_DIR="$ROOT/speed/trace-target"
nix develop ./spikes/rust-stack/player -c cargo build --release --features benchmark-work-counters --manifest-path spikes/rust-stack/player/Cargo.toml
SCHEMA="$ROOT/core/stride-4.7.2/schema.json"
: > "$OUT.partial"
for name in ${TRACE_LEVELS:-real-64d3d5f1d77b3fe14198c693 real-6aa65f0c574012395a0faddf real-66476d1f0e6c18cafbaaf355 scale-2400}; do
  if [[ "$name" == real-* ]]; then file="$ROOT/scaling/${REAL_SCREENS_DIR:-real-screens-v2}/$name.level.json"; mode=real-screen; else file="$ROOT/scaling/$name.level.json"; mode=synthetic; fi
  "$CARGO_TARGET_DIR/release/eggshell-spike-player" --benchmark-trace-host "$file" data/collision_table.json "$SCHEMA" 600 "$mode" \
    "$HOME/.local/share/eggshell/packs/original-v3-final" "$HOME/eggshell-remote/player-pack-files.sha256.json" \
    "$ROOT/player/presentation-stage/view-metrics.json" | tee -a "$OUT.partial"
done
mv "$OUT.partial" "$OUT"
if [[ $# -ge 2 ]]; then
  diff "$ROOT/speed/trace-$2.txt" "$OUT"
  printf 'TRACE_EQUAL baseline=%s candidate=%s lines=%s\n' "$2" "$TAG" "$(wc -l < "$OUT")"
fi
printf 'TRACE_DONE tag=%s\n' "$TAG"
