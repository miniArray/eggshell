#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
if [[ -n "${EXPECTED_SOURCE_SHA:-}" ]]; then test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_SHA"; fi
export CORE_PROOF_DIR="$HOME/eggshell-remote/artifacts/full-rust-ab/core/foundations"
export CORE_ORACLE_DIR="$HOME/eggshell-remote/artifacts/full-rust-ab/core/stride-4.7.2"
GODOT=${GODOT:-godot}
[[ $("$GODOT" --version) == 4.7.2.* ]]
gdformat spikes/rust-stack/oracle/world_counts.gd spikes/rust-stack/oracle/world_proof.gd
gdlint spikes/rust-stack/oracle/world_counts.gd spikes/rust-stack/oracle/world_proof.gd
nix-shell spikes/rust-stack/oracle/prepared.sh
"$GODOT" --headless --path . --script spikes/rust-stack/oracle/world_counts.gd -- "$PWD/tests/fixtures/stride.level.json" "$CORE_PROOF_DIR/world-counts.json" 2>&1 | tee "$CORE_PROOF_DIR/world-counts.log"
if grep -E 'SCRIPT ERROR|ERROR:' "$CORE_PROOF_DIR/world-counts.log"; then exit 1; fi
grep WORLD_COUNTS_ORACLE_DONE "$CORE_PROOF_DIR/world-counts.log"
cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test world_counts
cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test world_counts -- --ignored --nocapture
cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test stride_uninterrupted -- --ignored --nocapture
cargo clippy --locked --manifest-path spikes/rust-stack/core/Cargo.toml --all-targets -- -D warnings
shellcheck -s bash spikes/rust-stack/oracle/counts.sh
printf 'COUNTS_API_DONE source=%s api=World.flowers_target+i64,World.redcoins_target+i64 defaults=0 source_semantics=bounded_integer_then_max_zero inferred_from_placements=false v10_schema=unchanged target_gameplay=refused\n' "$(git rev-parse HEAD)"
