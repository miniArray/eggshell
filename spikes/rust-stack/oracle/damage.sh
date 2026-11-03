#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
if [[ -n "${EXPECTED_SOURCE_SHA:-}" ]]; then test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_SHA"; fi
rustc --version
cargo --version
export CORE_DAMAGE_DIR="$HOME/eggshell-remote/artifacts/full-rust-ab/core/stride.damage-4.7.2"
export CORE_ORACLE_DIR="$HOME/eggshell-remote/artifacts/full-rust-ab/core/stride-4.7.2"
cargo fmt --manifest-path spikes/rust-stack/core/Cargo.toml
cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --lib
cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test stride_damage_next --test stride_session --test stride_uninterrupted --test stride_overflow -- --ignored --nocapture
GODOT=${GODOT:-godot}
[[ $("$GODOT" --version) == 4.7.2.* ]]
git diff --exit-code 297ada9a022d0ddc297dd2d4091c5dccfab4531e -- src tests/fixtures
for tick in 153 190 220 350; do
  "$GODOT" --headless --path . --script spikes/rust-stack/oracle/continue.gd -- "$PWD/tests/fixtures/stride.level.json" "$PWD/tests/fixtures/stride.damage.input.json" "$CORE_DAMAGE_DIR/snapshots.v10.stream" "$CORE_DAMAGE_DIR/rust-uninterrupted-$tick.v10" "$tick" 2>&1 | tee "$CORE_DAMAGE_DIR/b-to-a-$tick.log"
  if grep -E 'SCRIPT ERROR|ERROR:' "$CORE_DAMAGE_DIR/b-to-a-$tick.log"; then exit 1; fi
  grep B_TO_A_CONTINUATION_DONE "$CORE_DAMAGE_DIR/b-to-a-$tick.log"
done
cargo clippy --locked --manifest-path spikes/rust-stack/core/Cargo.toml --all-targets -- -D warnings
printf 'DAMAGE_VERTICAL_DONE source=%s target_admission=refused\n' "$(git rev-parse HEAD)"
