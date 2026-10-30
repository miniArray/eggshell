#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix linuxPackages.perf
# aka only. Self-time profile of 300 idle simulation steps on the real screens.
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
ROOT="$HOME/eggshell-remote/artifacts/full-rust-ab"
D="$ROOT/speed/sim-self-$(git rev-parse --short HEAD)-$(date -u +%Y%m%dT%H%M%S)-$$"
mkdir "$D"
export CARGO_TARGET_DIR="$ROOT/speed/profile-target"
export RUSTFLAGS='-C force-frame-pointers=yes -C debuginfo=2'
nix develop ./spikes/rust-stack/player -c cargo build --release --manifest-path spikes/rust-stack/player/Cargo.toml
SCHEMA="$ROOT/core/stride-4.7.2/schema.json"
for name in "$@"; do
  perf record -q -e cpu-clock:u -F 4999 --call-graph fp -o "$D/$name.perf.data" -- \
    "$CARGO_TARGET_DIR/release/eggshell-spike-player" --benchmark-profile-host \
    "$ROOT/scaling/${REAL_SCREENS_DIR:-real-screens-v2}/$name.level.json" src/level/collision_table.json "$SCHEMA" 300 real-screen
  printf 'SELF_PROFILE %s\n' "$name"
  perf report -i "$D/$name.perf.data" --stdio --no-children -g none --sort symbol 2>/dev/null \
    | grep -E "^ +[0-9]" | head -15 || true
  printf 'CHILDREN_PROFILE %s\n' "$name"
  perf report -i "$D/$name.perf.data" --stdio --children -g none --sort symbol 2>/dev/null \
    | grep -E "^ +[0-9]" | head -25 || true
done
printf 'SIM_SELF_PROFILE_DONE artifact=%s\n' "$D"
