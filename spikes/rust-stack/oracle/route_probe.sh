#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
# aka only, diagnosis. Usage: route_probe.sh FIXTURE FIRST LAST STRIDE FIELD,FIELD...
# Writes the fixture's current normal route, then prints Godot's entity rows on it
# (entity_probe.sh); a field written @name is a player field.
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
out="$HOME/eggshell-remote/artifacts/full-rust-ab/core"
mkdir -p "$out"
python3 spikes/rust-stack/oracle/normal_routes.py "$1" "$out/$1.input.json"
nix-shell spikes/rust-stack/oracle/entity_probe.sh "$@"
