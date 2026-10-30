#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
if [[ -n "${EXPECTED_SOURCE_SHA:-}" ]]; then test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_SHA"; fi
git diff --exit-code 297ada9a022d0ddc297dd2d4091c5dccfab4531e -- src tests/fixtures
fixture=${1:-bounce}
[[ "$fixture" == bounce || "$fixture" == bounce.pad || "$fixture" == lagoon || "$fixture" == collections || "$fixture" == actors_target ]]
base=${fixture%%.*}
export CORE_FIXTURE_INPUT="$PWD/tests/fixtures/$fixture.input.json"
export CORE_FIXTURE_LEVEL="$PWD/tests/fixtures/$base.level.json"
if [[ "$fixture" == bounce.pad || "$fixture" == collections || "$fixture" == actors_target ]]; then export CORE_FIXTURE_INPUT="$HOME/eggshell-remote/artifacts/full-rust-ab/core/$fixture.input.json"; fi
if [[ "$fixture" == collections || "$fixture" == actors_target ]]; then export CORE_FIXTURE_LEVEL="$PWD/spikes/rust-stack/core/tests/fixtures/$fixture.level.json"; fi
export CORE_FIXTURE="$fixture"
export CORE_FIXTURE_DIR="$HOME/eggshell-remote/artifacts/full-rust-ab/core/$fixture-4.7.2"
if [[ ! -f "$CORE_FIXTURE_DIR/snapshots.v10.stream" ]]; then nix-shell spikes/rust-stack/oracle/run.sh "$fixture"; fi
cargo fmt --manifest-path spikes/rust-stack/core/Cargo.toml
GODOT=${GODOT:-godot}
[[ $("$GODOT" --version) == 4.7.2.* ]]
if [[ "$fixture" == actors_target ]]; then
  gdformat spikes/rust-stack/oracle/actor_pictures.gd
  gdlint spikes/rust-stack/oracle/actor_pictures.gd
  "$GODOT" --headless --path . --script spikes/rust-stack/oracle/actor_pictures.gd -- "$CORE_FIXTURE_LEVEL" "$CORE_FIXTURE_DIR/snapshots.v10.stream" "$CORE_FIXTURE_DIR/pictures.json" 2>&1 | tee "$CORE_FIXTURE_DIR/pictures.log"
  if grep -E 'SCRIPT ERROR|ERROR:' "$CORE_FIXTURE_DIR/pictures.log"; then exit 1; fi
  grep ACTOR_PICTURES_ORACLE_DONE "$CORE_FIXTURE_DIR/pictures.log"
fi
cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --lib
cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test fixture_parity -- --ignored --nocapture
GODOT=${GODOT:-godot}
[[ $("$GODOT" --version) == 4.7.2.* ]]
branches=(1 6 11 70 75 90 160 220 350)
if [[ "$fixture" == actors_target ]]; then branches+=(780 790 791 1000 1080 1100 1200); fi
for tick in "${branches[@]}"; do
  "$GODOT" --headless --path . --script spikes/rust-stack/oracle/continue.gd -- "$CORE_FIXTURE_LEVEL" "$CORE_FIXTURE_INPUT" "$CORE_FIXTURE_DIR/snapshots.v10.stream" "$CORE_FIXTURE_DIR/rust-uninterrupted-$tick.v10" "$tick" 2>&1 | tee "$CORE_FIXTURE_DIR/b-to-a-$tick.log"
  if grep -E 'SCRIPT ERROR|ERROR:' "$CORE_FIXTURE_DIR/b-to-a-$tick.log"; then exit 1; fi
  grep B_TO_A_CONTINUATION_DONE "$CORE_FIXTURE_DIR/b-to-a-$tick.log"
done
cargo clippy --locked --manifest-path spikes/rust-stack/core/Cargo.toml --all-targets -- -D warnings
shellcheck -s bash spikes/rust-stack/oracle/fixture.sh
printf 'NEXT_FIXTURE_DONE source=%s fixture=%s api=VisualState.scale_optional_ratio target_admission=refused\n' "$(git rev-parse HEAD)" "$fixture"
