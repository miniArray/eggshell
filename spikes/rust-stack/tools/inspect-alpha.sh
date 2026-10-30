#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix python3 python3Packages.pillow
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
python3 spikes/rust-stack/tools/inspect-alpha.py
bash spikes/rust-stack/tools/inspect-godot-alpha-source.sh
