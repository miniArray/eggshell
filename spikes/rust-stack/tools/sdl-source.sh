#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash nix curl coreutils
set -euo pipefail
export NIX_CONFIG='builders ='
test "$(hostname)" = aka
nix config show | grep '^builders ='
nix store prefetch-file --json https://www.libsdl.org/release/SDL2-2.32.10.tar.gz
