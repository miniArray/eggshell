#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
bash spikes/rust-stack/core/lint.sh
export CORE_STRIDE=1
export CORE_ORACLE_DIR="$HOME/eggshell-remote/artifacts/full-rust-ab/core/stride-4.7.2"
export CORE_PROOF_DIR="$HOME/eggshell-remote/artifacts/full-rust-ab/core/foundations"
nix-shell spikes/rust-stack/core/check.sh
bash spikes/rust-stack/oracle/continuation.sh
bash spikes/rust-stack/oracle/run.sh stride.damage
printf 'STRIDE_MILESTONE_DONE target_admission=blocked\n'
