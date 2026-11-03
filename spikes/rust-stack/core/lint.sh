#!/usr/bin/env nix-shell
#! nix-shell toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
nixfmt spikes/rust-stack/core/toolchain.nix
shellcheck -s bash spikes/rust-stack/core/*.sh
printf 'CORE_LINT_DONE\n'
