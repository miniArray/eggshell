#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils python3
# aka only, in the player dev shell. Usage: route-search.sh LEVEL IMAGE STEPS
# Tries walk-and-hop routes (walk right, hop every 60 steps, with a shifted hop phase)
# until the scene draws IMAGE (a pack file name part); prints the route and its first
# and last drawn calls, and writes the route to /tmp/screens-found-route.json.
set -euo pipefail
[[ $(hostname) == aka ]]
level=$1 image=$2 steps=$3
C=$HOME/eggshell-remote/artifacts/full-rust-ab/core
route=$(mktemp --suffix=.json)
for phase in $(seq 0 4 56); do
  python3 -c "import json,sys; p,n=int(sys.argv[1]),int(sys.argv[2]); print(json.dumps([6 if (i+p)%60>=46 else 2 for i in range(n)]))" "$phase" "$steps" > "$route"
  found=$(HELD_TRACE_IMAGE=$image cargo run --quiet --release --manifest-path spikes/rust-stack/player/Cargo.toml -- --held-trace "$level" \
    src/level/collision_table.json "$C/stride-4.7.2/schema.json" "$HOME/.local/share/eggshell/packs/original-v3-final" \
    "$HOME/eggshell-remote/player-pack-files.sha256.json" \
    "$HOME/eggshell-remote/artifacts/full-rust-ab/player/presentation-stage/view-metrics.json" "$route" 2>&1 |
    grep '^HELD_TRACE_IMAGE' | awk '{print $2}' | sed -n '1p;$p' | tr '\n' ' ' || true)
  if [[ -n "$found" ]]; then
    printf 'ROUTE_FOUND phase=%s calls=%s\n' "$phase" "$found"
    cp "$route" /tmp/screens-found-route.json
    break
  fi
done
rm -f "$route"
