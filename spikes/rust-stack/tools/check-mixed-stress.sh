#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix ruff shellcheck
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
ruff check --select I --fix spikes/rust-stack/tools/generate-scaling.py spikes/rust-stack/tools/bundle-player.py
ruff format spikes/rust-stack/tools/generate-scaling.py spikes/rust-stack/tools/bundle-player.py
ruff check spikes/rust-stack/tools/generate-scaling.py spikes/rust-stack/tools/bundle-player.py
shellcheck --shell=bash spikes/rust-stack/tools/launch-owned-stress.sh
rust() { nix develop ./spikes/rust-stack/player -c "$@"; }
rust cargo fmt --manifest-path spikes/rust-stack/core/Cargo.toml
rust cargo fmt --manifest-path spikes/rust-stack/player/Cargo.toml
rust cargo test --manifest-path spikes/rust-stack/player/Cargo.toml --lib
nix-shell spikes/rust-stack/tools/generate-scaling.py --stress --mixed
ROOT="$HOME/eggshell-remote/artifacts/full-rust-ab/scaling/mixed-v2"
SCHEMA="$HOME/eggshell-remote/artifacts/full-rust-ab/core/stride-4.7.2/schema.json"
for name in mix-500 mix-2000 mix-500-dark wide-400-dark; do
  rust cargo run --manifest-path spikes/rust-stack/player/Cargo.toml -- --benchmark-host-check \
    "$ROOT/$name.level.json" src/level/collision_table.json "$SCHEMA" 120
  rust cargo run --manifest-path spikes/rust-stack/player/Cargo.toml -- --benchmark-zoom-range \
    "$ROOT/$name.level.json" src/level/collision_table.json
done
rust cargo run --manifest-path spikes/rust-stack/player/Cargo.toml -- --validate-assets \
  "$ROOT/mix-500-dark.level.json" src/level/collision_table.json \
  "$HOME/.local/share/eggshell/packs/original-v3-final" "$HOME/eggshell-remote/player-pack-files.sha256.json" \
  "$HOME/eggshell-remote/artifacts/full-rust-ab/player/presentation-stage/view-metrics.json" "$ROOT/mixed-asset-bindings.json"
printf 'MIXED_HOST_CHECKS_DONE benchmark_unverified_level=true saves_disabled=true\n'
