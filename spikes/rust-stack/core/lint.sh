#!/usr/bin/env nix-shell
#! nix-shell toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
nixfmt spikes/rust-stack/core/toolchain.nix
gdformat spikes/rust-stack/oracle/*.gd
ruff format spikes/rust-stack/oracle/*.py
ruff check --fix spikes/rust-stack/oracle/*.py
gdlint spikes/rust-stack/oracle/*.gd
shellcheck -s bash spikes/rust-stack/core/*.sh spikes/rust-stack/oracle/*.sh
printf 'CORE_LINT_DONE\n'
printf 'CORE_TARGET_ADMISSION_BLOCKED Only original Stride/Bounce dry-land slices are implemented; no target gameplay/performance admission\n'
