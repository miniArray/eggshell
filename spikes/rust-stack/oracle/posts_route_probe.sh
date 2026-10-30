#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
GODOT=${GODOT:-godot}
[[ $("$GODOT" --version) == 4.7.2.* ]]
gdformat spikes/rust-stack/oracle/posts_route_probe.gd
gdlint spikes/rust-stack/oracle/posts_route_probe.gd
"$GODOT" --headless --path . --script spikes/rust-stack/oracle/posts_route_probe.gd
