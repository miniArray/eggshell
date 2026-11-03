#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix shellcheck
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
ROOT="$HOME/eggshell-remote/artifacts/full-rust-ab"
D="$ROOT/speed/terrain-index-check-$(date -u +%Y%m%dT%H%M%S)-$$"
mkdir "$D"
printf 'TERRAIN_INDEX_ARTIFACT=%s\n' "$D"
rust() { nix develop ./spikes/rust-stack/player -c "$@"; }
rust cargo fmt --manifest-path spikes/rust-stack/core/Cargo.toml
rust cargo fmt --manifest-path spikes/rust-stack/player/Cargo.toml
shellcheck --shell=bash spikes/rust-stack/tools/check-terrain-index.sh spikes/rust-stack/tools/profile-real-cost.sh
rust cargo test --release --manifest-path spikes/rust-stack/core/Cargo.toml --lib indexed_collision_matches_linear_on_all_public_level_fixtures -- --nocapture
export TERRAIN_EQ_LEVELS
TERRAIN_EQ_LEVELS=$(printf '%s:' "$ROOT"/scaling/real-screens-v2/real-*.level.json)
TERRAIN_EQ_LEVELS=${TERRAIN_EQ_LEVELS%:}
rust cargo test --release --manifest-path spikes/rust-stack/core/Cargo.toml --lib indexed_collision_matches_linear_on_private_real_maps -- --ignored --nocapture
rust cargo test --manifest-path spikes/rust-stack/player/Cargo.toml --lib --features benchmark-work-counters
rust cargo clippy --manifest-path spikes/rust-stack/player/Cargo.toml --features benchmark-work-counters --all-targets -- -D warnings
rust cargo clippy --manifest-path spikes/rust-stack/core/Cargo.toml --lib --tests -- -D warnings
rust cargo build --release --manifest-path spikes/rust-stack/player/Cargo.toml
SCHEMA="$ROOT/core/stride-4.7.2/schema.json"
for name in real-64d3d5f1d77b3fe14198c693 real-6aa65f0c574012395a0faddf real-66476d1f0e6c18cafbaaf355 scale-2400; do
  if [[ "$name" == real-* ]]; then file="$ROOT/scaling/real-screens-v2/$name.level.json"; mode=real-screen; else file="$ROOT/scaling/$name.level.json"; mode=synthetic; fi
  spikes/rust-stack/player/target/release/eggshell-spike-player --benchmark-profile-host "$file" data/collision_table.json "$SCHEMA" 300 "$mode" | tee "$D/$name.profile.txt"
done
rust cargo build --release --features benchmark-work-counters --manifest-path spikes/rust-stack/player/Cargo.toml
for name in real-64d3d5f1d77b3fe14198c693 real-6aa65f0c574012395a0faddf real-66476d1f0e6c18cafbaaf355 scale-2400; do
  if [[ "$name" == real-* ]]; then file="$ROOT/scaling/real-screens-v2/$name.level.json"; mode=real-screen; original="$HOME/.local/share/eggshell-run/corpus/levels/${name#real-}.json"; else file="$ROOT/scaling/$name.level.json"; mode=synthetic; original=-; fi
  spikes/rust-stack/player/target/release/eggshell-spike-player --benchmark-work-host "$file" data/collision_table.json "$SCHEMA" 300 "$mode" "$original" \
    "$HOME/.local/share/eggshell/packs/original-v3-final" "$HOME/eggshell-remote/player-pack-files.sha256.json" \
    "$ROOT/player/presentation-stage/view-metrics.json" "$D/$name.work.json"
done
printf 'TERRAIN_INDEX_CHECK_DONE artifact=%s equality=exact-unreordered-world-hud-tint-quads-all-300-ticks-all-3-zooms\n' "$D"
