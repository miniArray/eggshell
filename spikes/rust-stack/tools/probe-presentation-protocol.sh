#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix
set -euo pipefail
export NIX_CONFIG='builders ='
test "$(hostname)" = aka
cd spikes/rust-stack/player
protocols=$(nix eval --impure --raw --expr 'let f=builtins.getFlake (toString ./.); p=import f.inputs.nixpkgs {system="x86_64-linux";}; in p.wayland-protocols.outPath')
printf 'WAYLAND_PROTOCOL_SOURCE %s\n' "$protocols"
cat "$protocols/share/wayland-protocols/stable/presentation-time/presentation-time.xml"
