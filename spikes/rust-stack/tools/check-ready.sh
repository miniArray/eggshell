#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix git
set -euo pipefail
export NIX_CONFIG='builders ='
test "$(hostname)" = aka
bash spikes/rust-stack/tools/check-tools.sh
bash spikes/rust-stack/tools/check-presentation-stage.sh
printf 'RUST_PLAYER_READY_CHECK_DONE source=%s core_tree=%s\n' "$(git rev-parse HEAD)" "$(git rev-parse HEAD:spikes/rust-stack/core)"
