#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
if [[ -n "${EXPECTED_SOURCE_SHA:-}" ]]; then test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_SHA"; fi
git diff --exit-code 297ada9a022d0ddc297dd2d4091c5dccfab4531e -- src tests/fixtures
GODOT=${GODOT:-godot}
[[ $("$GODOT" --version) == 4.7.2.* ]]
printf 'VERIFICATION_DEPENDENCY o11=Pad_Bounce_only p1=target_bridge immutable_preparation_is_not_gameplay_admission\n'
export CORE_PROOF_DIR="$HOME/eggshell-remote/artifacts/full-rust-ab/core/foundations"
export CORE_ORACLE_DIR="$HOME/eggshell-remote/artifacts/full-rust-ab/core/stride-4.7.2"
mkdir -p "$CORE_PROOF_DIR"
gdformat spikes/rust-stack/oracle/world_proof.gd
gdlint spikes/rust-stack/oracle/world_proof.gd
shellcheck -s bash spikes/rust-stack/oracle/prepared.sh
cargo fmt --manifest-path spikes/rust-stack/core/Cargo.toml
"$GODOT" --headless --path . --script spikes/rust-stack/oracle/world_proof.gd -- "$HOME/.local/share/eggshell-run/corpus/levels/6600ab52a3bb0805d316b9f1.json" "$CORE_PROOF_DIR/world.json" 2>&1 | tee "$CORE_PROOF_DIR/world.log"
if grep -E 'SCRIPT ERROR|ERROR:' "$CORE_PROOF_DIR/world.log"; then exit 1; fi
grep WORLD_ORACLE_DONE "$CORE_PROOF_DIR/world.log"
cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test prepared_geometry
cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test prepared_geometry -- --ignored --nocapture
cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test oracle_foundations unchanged_target_placements_terrain_transforms_and_contacts_match -- --ignored --nocapture
cargo clippy --locked --manifest-path spikes/rust-stack/core/Cargo.toml --all-targets -- -D warnings
printf 'PREPARED_API_DONE source=%s api=Placement.prepared+Map.bridges index=zero_based saved_support=index_plus_1 units=1/3600px target_gameplay=refused\n' "$(git rev-parse HEAD)"
