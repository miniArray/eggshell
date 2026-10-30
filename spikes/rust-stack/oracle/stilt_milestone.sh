#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
if [[ -n "${EXPECTED_SOURCE_SHA:-}" ]]; then test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_SHA"; fi
nix-shell spikes/rust-stack/oracle/actor_milestone.sh
nix-shell spikes/rust-stack/oracle/fixture.sh stilts_target
nix-shell spikes/rust-stack/oracle/fixture.sh stilts_target.knock
shellcheck -s bash spikes/rust-stack/oracle/stilt_milestone.sh
printf 'STILT_MILESTONE_DONE source=%s public_api=unchanged semantic_updates=e35_size_y+runtime_e1+typed_ordered_suffix token_history=stable birth=107 compaction=245 retained_ticks=138 birth_death_restore_cuts=106,107,108,244,245,246 knock_restore_cuts=25,26,27,77,78,79 target204=refused next=checkpoint+posts+clouds+requests+solids\n' "$(git rev-parse HEAD)"
