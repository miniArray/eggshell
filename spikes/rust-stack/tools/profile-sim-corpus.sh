#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix python3 linuxPackages.perf
# aka only. Usage: profile-sim-corpus.sh CORPUS_ID...
# Self-time profile of 600 simulation steps on the walk-hop route on private corpus levels (like
# profile-sim-self.sh, which profiles the real screens).
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
ROOT="$HOME/eggshell-remote/artifacts/full-rust-ab"
D="$ROOT/speed/sim-corpus-$(git rev-parse --short HEAD)-$(date -u +%Y%m%dT%H%M%S)-$$"
mkdir "$D"
export CARGO_TARGET_DIR="$ROOT/speed/profile-target"
export RUSTFLAGS='-C force-frame-pointers=yes -C debuginfo=2'
# The dev shell sets its own RUSTFLAGS; pass frame pointers and line tables inside it.
nix develop ./spikes/rust-stack/player -c env RUSTFLAGS="$RUSTFLAGS" CARGO_PROFILE_RELEASE_DEBUG=line-tables-only \
  cargo build --release --manifest-path spikes/rust-stack/player/Cargo.toml
SCHEMA="$ROOT/core/stride-4.7.2/schema.json"
# The pack parity walk-and-hop route (host-sim-corpus.sh writes the same file).
export HOST_SIM_INPUT="$ROOT/speed/host-sim-route.json"
python3 -c "
import json
print(json.dumps([2] * 40 + [6] * 14 + [2] * 20 + [8] + [0] * 12 + [2] * 30 + [0] * 8))" > "$HOST_SIM_INPUT"
for id in "$@"; do
  perf record -q -e cpu-clock:u -F 4999 --call-graph fp -o "$D/$id.perf.data" -- \
    "$CARGO_TARGET_DIR/release/eggshell-spike-player" --benchmark-profile-host \
    "$HOME/.local/share/eggshell-run/corpus/levels/$id.json" data/collision_table.json "$SCHEMA" 600 real-screen
  printf 'SELF_PROFILE %s\n' "$id"
  perf report -i "$D/$id.perf.data" --stdio --no-children -g none --sort symbol 2>/dev/null \
    | grep -E "^ +[0-9]" | head -15 || true
  printf 'HOT_LINES %s\n' "$id"
  perf report -i "$D/$id.perf.data" --stdio --no-children -g none --sort srcline 2>/dev/null \
    | grep -E "^ +[0-9]" | head -12 || true
  printf 'CALLERS %s\n' "$id"
  perf report -i "$D/$id.perf.data" --stdio --children -g none --sort symbol 2>/dev/null \
    | grep -E "^ +[0-9]" | grep -E 'eggshell_spike_core' | head -30 || true
done
printf 'SIM_CORPUS_PROFILE_DONE dir=%s\n' "$D"
