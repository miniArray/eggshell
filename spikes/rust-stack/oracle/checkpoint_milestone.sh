#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
if [[ -n "${EXPECTED_SOURCE_SHA:-}" ]]; then test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_SHA"; fi
nix-shell spikes/rust-stack/oracle/inactive_visibility.sh
nix-shell spikes/rust-stack/oracle/stilt_milestone.sh
nix-shell spikes/rust-stack/oracle/fixture.sh checkpoint_target
shellcheck -s bash spikes/rust-stack/oracle/checkpoint_milestone.sh spikes/rust-stack/oracle/inactive_visibility.sh spikes/rust-stack/oracle/evidence.sh spikes/rust-stack/oracle/fixture.sh spikes/rust-stack/oracle/run.sh
ruff check spikes/rust-stack/oracle/normal_routes.py
ruff format --check spikes/rust-stack/oracle/normal_routes.py
printf 'CHECKPOINT_MILESTONE_DONE source=%s public_api=unchanged semantics=o6+awards+checkpoint_recovery+persistent_collection_flags+original_inactive_visibility policy_boundary_cases=320 calls=2400 snapshots=2401 checkpoint_ticks=105 death=1334 reset=1635 input_resume=1638 post_reset_pickup=1673 critical_restores=entry+awards+exit+death+fade+reset+resume+pickup target204=refused next=posts+clouds+requests+solids\n' "$(git rev-parse HEAD)"
