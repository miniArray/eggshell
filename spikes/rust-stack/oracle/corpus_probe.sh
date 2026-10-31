#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
# aka only, diagnosis. Usage: corpus_probe.sh CORPUS_ID FIRST LAST STRIDE FIELD,FIELD... [CODE]
# Godot entity rows for a private corpus level on the pack parity route (900 ticks).
set -euo pipefail
[[ $(hostname) == aka ]]
GODOT=${GODOT:-godot}
[[ $("$GODOT" --version) == 4.7.2.* ]]
level="$HOME/.local/share/eggshell-run/corpus/levels/$1.json"
input="$HOME/eggshell-remote/artifacts/full-rust-ab/core/pack-parity/route-900.input.json"
"$GODOT" --headless --path . --script spikes/rust-stack/oracle/entity_probe.gd -- "$level" "$input" "$2" "$3" "$4" "$5" 2>&1 \
  | grep -E '^ENTITIES|ERROR' | if [[ -n "${6:-}" ]]; then grep -oE "tick=[0-9]+ player=[0-9,-]+|[^ ;|]+:$6@[^;]*"; else cat; fi
