#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
# aka only, diagnosis. Usage: bubble_probe_level.sh LEVEL.json FIRST LAST
# Idle input (no buttons) on any level; prints the bubble view per tick.
set -euo pipefail
[[ $(hostname) == aka ]]
GODOT=${GODOT:-godot}
[[ $("$GODOT" --version) == 4.7.2.* ]]
input=$(mktemp --suffix=.json)
python3 -c "import json,sys; print(json.dumps([0]*int(sys.argv[1])))" "$3" > "$input"
"$GODOT" --headless --path . --script spikes/rust-stack/oracle/bubble_probe.gd -- "$1" "$input" "$2" "$3" 2>&1 | grep -E '^BUBBLE|ERROR'
rm -f "$input"
