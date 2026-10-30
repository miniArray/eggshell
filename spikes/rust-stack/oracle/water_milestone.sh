#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
if [[ -n "${EXPECTED_SOURCE_SHA:-}" ]]; then test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_SHA"; fi
nix-shell spikes/rust-stack/oracle/bounce_milestone.sh
nix-shell spikes/rust-stack/oracle/fixture.sh lagoon
printf 'WATER_MILESTONE_DONE source=%s public_api=unchanged semantic_updates=swimming+wet_poses+liquid_motion v10_schema=unchanged target=refused next=target_runtime_closure\n' "$(git rev-parse HEAD)"
