#!/usr/bin/env bash
# aka only: Rust dump and Godot bubble view around a pack parity bubble mismatch.
set -euo pipefail
id=$1; first=$2; last=$3
nix-shell spikes/rust-stack/oracle/corpus_dump.sh "$id" "$first" "$last" | grep -oE 'mismatch.*|tick=[0-9]+ |cmode=[0-9]+ |cvx=[-0-9]+ |rx=[-0-9]+ |ry=[-0-9]+' | paste -sd' ' | sed 's/tick=/\ntick=/g'
echo
level="$HOME/.local/share/eggshell-run/corpus/levels/$id.json"
input="$HOME/eggshell-remote/artifacts/full-rust-ab/core/pack-parity/route-900.input.json"
godot --headless --path . --script spikes/rust-stack/oracle/bubble_probe.gd -- "$level" "$input" "$first" "$last" 2>&1 | grep -E '^BUBBLE' | cut -c1-200
