#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix python3 linuxPackages.perf
# aka only. Usage: host-sim-corpus.sh TICKS CORPUS_ID...
# Host step time (HOST_SIM_PROFILE: p50/p95/p99/max ms per step on the walk-hop route) on private corpus
# levels, release build without profiling flags. A host hint only; the Pro decides.
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
ROOT="$HOME/eggshell-remote/artifacts/full-rust-ab"
export CARGO_TARGET_DIR="$ROOT/speed/host-sim-target"
ticks=$1
shift
nix develop ./spikes/rust-stack/player -c cargo build -q --release --manifest-path spikes/rust-stack/player/Cargo.toml
SCHEMA="$ROOT/core/stride-4.7.2/schema.json"
# The pack parity walk-and-hop route, so walkers, runners and blocks get used.
route="$ROOT/speed/host-sim-route.json"
python3 -c "
import json
cycle = [2] * 40 + [6] * 14 + [2] * 20 + [8] + [0] * 12 + [2] * 30 + [0] * 8
print(json.dumps(cycle))" > "$route"
export HOST_SIM_INPUT="$route"
for id in "$@"; do
  # User-space instructions are the load-independent number on a busy host.
  perf stat -x, -e instructions:u -o "$ROOT/speed/host-sim-$id.perf" -- \
    "$CARGO_TARGET_DIR/release/eggshell-spike-player" --benchmark-profile-host \
    "$HOME/.local/share/eggshell-run/corpus/levels/$id.json" data/collision_table.json "$SCHEMA" "$ticks" real-screen \
    | sed -n 's/^HOST_SIM_PROFILE //p' | sed "s/^/$id /" | grep -o '^[0-9a-f]* \|"step_ms_p[0-9]*":[0-9.]*\|"step_ms_max":[0-9.]*' | tr '\n' ' '
  printf 'instructions_u=%s\n' "$(grep instructions "$ROOT/speed/host-sim-$id.perf" | cut -d, -f1)"
done
