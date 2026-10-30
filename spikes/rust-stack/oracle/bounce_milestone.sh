#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
if [[ -n "${EXPECTED_SOURCE_SHA:-}" ]]; then test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_SHA"; fi
nix-shell spikes/rust-stack/oracle/damage.sh
nix-shell spikes/rust-stack/oracle/fixture.sh bounce
nix-shell spikes/rust-stack/oracle/fixture.sh bounce.pad
nix-shell spikes/rust-stack/core/lint.sh
printf 'BOUNCE_MILESTONE_DONE source=%s api=VisualState.scale:Option<[f64;2]> defaults=None ratio_identity=1,1 v10=unchanged target=refused next=water\n' "$(git rev-parse HEAD)"
