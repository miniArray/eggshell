#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix linuxPackages.perf
# aka only. Usage: check-equal-and-speed.sh TAG BASELINE_TAG
# Formats, tests and lints core and player; proves the trace equals the baseline on
# the 9-level benchmark set; then prints host step times and self-time profiles.
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
TAG=$1
BASE=$2
ROOT="$HOME/eggshell-remote/artifacts/full-rust-ab"
export REAL_SCREENS_DIR=real-screens-v3
BENCH="real-64d3d5f1d77b3fe14198c693 real-6aa65f0c574012395a0faddf real-66476d1f0e6c18cafbaaf355 real-6600ab52a3bb0805d316b9f1 real-64625273d4802b03e9cd98d2 real-69ef3bb076aa6bf9fc85b8bb real-686904f725e59f7ef841ddba real-6a436c973e11434283469b06 real-6a737f7064c334870404d4e0"
export TRACE_LEVELS="$BENCH scale-2400"
rust() { nix develop ./spikes/rust-stack/player -c "$@"; }
rust cargo fmt --manifest-path spikes/rust-stack/core/Cargo.toml
rust cargo fmt --manifest-path spikes/rust-stack/player/Cargo.toml
rust cargo test --release --manifest-path spikes/rust-stack/core/Cargo.toml 2>&1 | grep -E '^test result|FAILED|panicked' || true
rust cargo test --release --manifest-path spikes/rust-stack/core/Cargo.toml >/dev/null
TERRAIN_EQ_LEVELS=$(for n in $BENCH; do printf '%s:' "$ROOT/scaling/$REAL_SCREENS_DIR/$n.level.json"; done)
export TERRAIN_EQ_LEVELS=${TERRAIN_EQ_LEVELS%:}
rust cargo test --release --manifest-path spikes/rust-stack/core/Cargo.toml --lib indexed_collision_matches_linear_on_private_real_maps -- --ignored 2>&1 | grep -E '^test result|FAILED|panicked'
rust cargo test --manifest-path spikes/rust-stack/player/Cargo.toml --lib --features benchmark-work-counters 2>&1 | grep -E '^test result|FAILED|panicked'
rust cargo clippy --manifest-path spikes/rust-stack/core/Cargo.toml --lib --tests -- -D warnings
rust cargo clippy --manifest-path spikes/rust-stack/player/Cargo.toml --features benchmark-work-counters --all-targets -- -D warnings
rust cargo clippy --manifest-path spikes/rust-stack/player/Cargo.toml --all-targets -- -D warnings
nix-shell spikes/rust-stack/tools/trace-equality.sh "$TAG" "$BASE" | grep -E 'TRACE_EQUAL|TRACE_DONE'
export CARGO_TARGET_DIR="$ROOT/speed/profile-target"
export RUSTFLAGS='-C force-frame-pointers=yes -C debuginfo=2'
rust cargo build --release --manifest-path spikes/rust-stack/player/Cargo.toml
SCHEMA="$ROOT/core/stride-4.7.2/schema.json"
D="$ROOT/speed/sim-self-$TAG"
mkdir -p "$D"
for name in $BENCH; do
  perf record -q -e cpu-clock:u -F 4999 --call-graph fp -o "$D/$name.perf.data" -- \
    "$CARGO_TARGET_DIR/release/eggshell-spike-player" --benchmark-profile-host \
    "$ROOT/scaling/$REAL_SCREENS_DIR/$name.level.json" data/collision_table.json "$SCHEMA" 300 real-screen 2>/dev/null \
    | grep -o 'step_ms_p50":[0-9.]*' | sed "s/^/STEP ${name:5:8} /"
done
for name in real-6a737f7064c334870404d4e0 real-6a436c973e11434283469b06 real-64d3d5f1d77b3fe14198c693; do
  printf 'TOP %s\n' "${name:5:8}"
  perf report -i "$D/$name.perf.data" --stdio --no-children -g none --sort symbol 2>/dev/null \
    | grep -E '^ +[0-9]' | sed -n 1,8p | cut -c1-120 || true
done
printf 'CHECK_EQUAL_AND_SPEED_DONE tag=%s\n' "$TAG"
