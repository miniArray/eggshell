#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils git nix ruff shellcheck nixfmt
set -euo pipefail
export NIX_CONFIG='builders ='
test "$(hostname)" = aka
nix config show | grep '^builders ='
ruff check --select I --fix spikes/rust-stack/tools
ruff format spikes/rust-stack/tools
ruff check spikes/rust-stack/tools
shellcheck --shell=bash spikes/rust-stack/tools/*.sh
nixfmt spikes/rust-stack/player/flake.nix spikes/rust-stack/player/sdl2.nix
nixfmt --check spikes/rust-stack/player/flake.nix spikes/rust-stack/player/sdl2.nix
