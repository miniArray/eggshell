#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
if [[ -n "${EXPECTED_SOURCE_SHA:-}" ]]; then test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_SHA"; fi
nix-shell spikes/rust-stack/oracle/water_milestone.sh
nix-shell spikes/rust-stack/oracle/fixture.sh collections
if [[ -f "$HOME/eggshell-remote/artifacts/full-rust-ab/routes/target-search-v2/finish.v10" ]]; then
  cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test route_inspect -- --ignored --nocapture
fi
printf 'COLLECTION_MILESTONE_DONE source=%s required_target_modules=pickup+item_star+decor_default original_target_204=refused verification_course_is_not_benchmark=true public_api=unchanged\n' "$(git rev-parse HEAD)"
