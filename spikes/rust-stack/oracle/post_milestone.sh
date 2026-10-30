#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
if [[ -n "${EXPECTED_SOURCE_SHA:-}" ]]; then test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_SHA"; fi
nix-shell spikes/rust-stack/oracle/fixture.sh posts_target.pound
nix-shell spikes/rust-stack/oracle/fixture.sh posts_target.duck
nix-shell spikes/rust-stack/oracle/checkpoint_milestone.sh
nix-shell spikes/rust-stack/oracle/fixture.sh posts_target
cargo fmt --manifest-path spikes/rust-stack/core/Cargo.toml -- --check
cargo clippy --locked --manifest-path spikes/rust-stack/core/Cargo.toml --all-targets -- -D warnings
shellcheck -s bash spikes/rust-stack/oracle/post_milestone.sh spikes/rust-stack/oracle/posts_route_probe.sh spikes/rust-stack/oracle/fixture.sh spikes/rust-stack/oracle/evidence.sh
gdformat spikes/rust-stack/oracle/posts_geometry.gd spikes/rust-stack/oracle/posts_route_probe.gd spikes/rust-stack/oracle/actor_pictures.gd
gdlint spikes/rust-stack/oracle/posts_geometry.gd spikes/rust-stack/oracle/posts_route_probe.gd spikes/rust-stack/oracle/actor_pictures.gd
ruff check spikes/rust-stack/oracle/normal_routes.py
ruff format --check spikes/rust-stack/oracle/normal_routes.py
printf 'POST_MILESTONE_DONE source=%s semantics=o23+DOWN+pound_phases+live_static_post_projection natural_changes=121,193,265 heights=64,32,16 impact=3 old_live_snapshots=801 same_step_floor=true moving_cloud_carry=unproven all_midphase_ordering=unproven public_api=unchanged target204=refused next=clouds+requests+remaining_runtime\n' "$(git rev-parse HEAD)"
