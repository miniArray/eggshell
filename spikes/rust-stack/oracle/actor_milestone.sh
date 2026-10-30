#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
if [[ -n "${EXPECTED_SOURCE_SHA:-}" ]]; then test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_SHA"; fi
nix-shell spikes/rust-stack/oracle/collection_milestone.sh
nix-shell spikes/rust-stack/oracle/fixture.sh actors_target
printf 'ACTOR_MILESTONE_DONE source=%s public_api=unchanged semantic_updates=e2+e3+e5+capture+full_lifetime head_sampling=enemy_head_axis_aligned_bbox not_rotating_fallback=true target204=refused next=runtime_entities+checkpoint+posts+clouds+requests\n' "$(git rev-parse HEAD)"
