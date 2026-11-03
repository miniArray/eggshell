#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils python3
# aka only, in the player dev shell. Usage: spit-search.sh LEVEL
# Tries "walk right N steps, lick, wait, spit" routes until an enemy is caught and spat,
# and prints the --held-trace rows of the first such route.
set -euo pipefail
[[ $(hostname) == aka ]]
level=$1
C=$HOME/eggshell-remote/artifacts/full-rust-ab/core
input=$(mktemp --suffix=.json)
for walk in $(seq 20 10 400); do
  python3 -c "import json,sys; w=int(sys.argv[1]); print(json.dumps([2]*w+[8]+[0]*20+[8]+[0]*80))" "$walk" > "$input"
  out=$(cargo run --quiet --release --manifest-path spikes/rust-stack/player/Cargo.toml -- --held-trace "$level" \
    data/collision_table.json "$C/stride-4.7.2/schema.json" "$HOME/.local/share/eggshell/packs/original-v3-final" \
    "$HOME/eggshell-remote/player-pack-files.sha256.json" \
    "$HOME/eggshell-remote/artifacts/full-rust-ab/player/presentation-stage/view-metrics.json" "$input" 2>&1 || true)
  if grep -q 'held=false' <<<"$out" && grep -q 'held=true' <<<"$out"; then
    printf 'SPIT_ROUTE walk=%s\n' "$walk"
    grep HELD_TRACE <<<"$out" | head -60
    break
  fi
done
rm -f "$input"
