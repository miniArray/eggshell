#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
# aka only, diagnosis. Usage: bubble_probe.sh FIXTURE FIRST LAST
set -euo pipefail
[[ $(hostname) == aka ]]
GODOT=${GODOT:-godot}
[[ $("$GODOT" --version) == 4.7.2.* ]]
base=${1%%.*}
level="$PWD/spikes/rust-stack/core/tests/fixtures/$base.level.json"
input="$HOME/eggshell-remote/artifacts/full-rust-ab/core/$1.input.json"
timeout 900 "$GODOT" --headless --path . --script spikes/rust-stack/oracle/bubble_probe.gd -- "$level" "$input" "$2" "$3" 2>&1 | grep -E '^BUBBLE|ERROR'
