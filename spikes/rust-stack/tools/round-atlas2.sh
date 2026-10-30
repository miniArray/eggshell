#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix
# aka only. Atlas tests and lints, then self-time profiles of the slowest benchmark levels.
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
nix-shell spikes/rust-stack/tools/check-atlas.sh
REAL_SCREENS_DIR=real-screens-v3 nix-shell spikes/rust-stack/tools/profile-sim-self.sh \
  real-6a737f7064c334870404d4e0 real-6a436c973e11434283469b06 real-64d3d5f1d77b3fe14198c693 2>&1 \
  | grep -E 'HOST_SIM_PROFILE|SELF_PROFILE|CHILDREN_PROFILE|^ +[0-9]|DONE' | cut -c1-150
