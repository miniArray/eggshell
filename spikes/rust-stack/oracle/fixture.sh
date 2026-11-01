#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
if [[ -n "${EXPECTED_SOURCE_SHA:-}" ]]; then test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_SHA"; fi
git diff --exit-code 297ada9a022d0ddc297dd2d4091c5dccfab4531e -- src tests/fixtures
fixture=${1:-bounce}
[[ "$fixture" == bounce || "$fixture" == bounce.pad || "$fixture" == bounce.moves || "$fixture" == stride.eat || "$fixture" == lagoon || "$fixture" == collections || "$fixture" == actors_target || "$fixture" == stilts_target || "$fixture" == stilts_target.knock || "$fixture" == checkpoint_target || "$fixture" == posts_target || "$fixture" == posts_target.pound || "$fixture" == posts_target.duck || "$fixture" == blocks_target || "$fixture" == spans_target || "$fixture" == flats_target || "$fixture" == hards_target || "$fixture" == falls_target || "$fixture" == grows_target || "$fixture" == gates_target || "$fixture" == ledges_target || "$fixture" == stems_target || "$fixture" == flowers_target || "$fixture" == switches_target || "$fixture" == shells_target || "$fixture" == armored_target || "$fixture" == spears_target || "$fixture" == lifts_target || "$fixture" == snowflow_target || "$fixture" == fish_target || "$fixture" == melons_target || "$fixture" == thieves_target || "$fixture" == rollers_target || "$fixture" == shooters_target || "$fixture" == wings_target || "$fixture" == launchers_target || "$fixture" == sprouts_target || "$fixture" == jugglers_target || "$fixture" == bulks_target || "$fixture" == gusts_target || "$fixture" == hounds_target || "$fixture" == spores_target || "$fixture" == hangs_target || "$fixture" == eggblocks_target || "$fixture" == pillars_target || "$fixture" == balloons_target || "$fixture" == clears_target || "$fixture" == dice_target || "$fixture" == decor_target || "$fixture" == rejoin_target || "$fixture" == hopstems_target || "$fixture" == petals_target || "$fixture" == spitters_target || "$fixture" == elements_target || "$fixture" == spins_target || "$fixture" == sceneryledges_target || "$fixture" == thorns_target || "$fixture" == discs_target || "$fixture" == runners_target || "$fixture" == slimes_target || "$fixture" == spines_target ]]
base=${fixture%%.*}
# Lanes gate concurrently on aka and share the fixture artifact directory: one run of a
# fixture at a time.
mkdir -p "$HOME/eggshell-remote/artifacts/full-rust-ab/core"
exec 9>"$HOME/eggshell-remote/artifacts/full-rust-ab/core/$fixture.lock"
flock 9
authored=0
case "$base" in collections|actors_target|stilts_target|checkpoint_target|posts_target|blocks_target|spans_target|flats_target|hards_target|falls_target|grows_target|gates_target|ledges_target|stems_target|flowers_target|switches_target|shells_target|armored_target|spears_target|lifts_target|snowflow_target|fish_target|melons_target|thieves_target|rollers_target|shooters_target|wings_target|launchers_target|sprouts_target|jugglers_target|bulks_target|gusts_target|hounds_target|spores_target|hangs_target|eggblocks_target|pillars_target|balloons_target|clears_target|dice_target|decor_target|rejoin_target|hopstems_target|petals_target|spitters_target|elements_target|spins_target|sceneryledges_target|thorns_target|discs_target|runners_target|slimes_target|spines_target) authored=1 ;; esac
export CORE_FIXTURE_INPUT="$PWD/tests/fixtures/$fixture.input.json"
export CORE_FIXTURE_LEVEL="$PWD/tests/fixtures/$base.level.json"
if [[ "$fixture" == bounce.pad || "$fixture" == bounce.moves || "$fixture" == stride.eat || "$authored" == 1 ]]; then export CORE_FIXTURE_INPUT="$HOME/eggshell-remote/artifacts/full-rust-ab/core/$fixture.input.json"; fi
if [[ "$authored" == 1 ]]; then export CORE_FIXTURE_LEVEL="$PWD/spikes/rust-stack/core/tests/fixtures/$base.level.json"; fi
export CORE_FIXTURE="$fixture"
export CORE_FIXTURE_DIR="$HOME/eggshell-remote/artifacts/full-rust-ab/core/$fixture-4.7.2"
need_export=0
if [[ ! -f "$CORE_FIXTURE_DIR/snapshots.v10.stream" ]]; then need_export=1; fi
if [[ "$fixture" == bounce.pad || "$fixture" == bounce.moves || "$fixture" == stride.eat || "$authored" == 1 ]]; then
  mkdir -p "$CORE_FIXTURE_DIR"
  python3 spikes/rust-stack/oracle/normal_routes.py "$fixture" "$CORE_FIXTURE_DIR/expected.input.json"
  if ! cmp -s "$CORE_FIXTURE_DIR/expected.input.json" "$CORE_FIXTURE_INPUT"; then need_export=1; fi
fi
if [[ "$need_export" == 1 ]]; then nix-shell spikes/rust-stack/oracle/run.sh "$fixture"; fi
cargo fmt --manifest-path spikes/rust-stack/core/Cargo.toml
GODOT=${GODOT:-godot}
[[ $("$GODOT" --version) == 4.7.2.* ]]
if [[ "$fixture" == actors_target || "$base" == stilts_target || "$fixture" == checkpoint_target || "$base" == posts_target ]]; then
  gdformat spikes/rust-stack/oracle/actor_pictures.gd
  gdlint spikes/rust-stack/oracle/actor_pictures.gd
  "$GODOT" --headless --path . --script spikes/rust-stack/oracle/actor_pictures.gd -- "$CORE_FIXTURE_LEVEL" "$CORE_FIXTURE_DIR/snapshots.v10.stream" "$CORE_FIXTURE_DIR/pictures.json" 2>&1 | tee "$CORE_FIXTURE_DIR/pictures.log"
  if grep -E 'SCRIPT ERROR|ERROR:' "$CORE_FIXTURE_DIR/pictures.log"; then exit 1; fi
  grep ACTOR_PICTURES_ORACLE_DONE "$CORE_FIXTURE_DIR/pictures.log"
fi
if [[ "$fixture" == posts_target.pound ]]; then
  gdformat spikes/rust-stack/oracle/posts_geometry.gd
  gdlint spikes/rust-stack/oracle/posts_geometry.gd
  "$GODOT" --headless --path . --script spikes/rust-stack/oracle/posts_geometry.gd -- "$CORE_FIXTURE_LEVEL" "$CORE_FIXTURE_INPUT" "$CORE_FIXTURE_DIR/geometry.json" 2>&1 | tee "$CORE_FIXTURE_DIR/geometry.log"
  if grep -E 'SCRIPT ERROR|ERROR:' "$CORE_FIXTURE_DIR/geometry.log"; then exit 1; fi
  grep POST_GEOMETRY_ORACLE_DONE "$CORE_FIXTURE_DIR/geometry.log"
  cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --lib post_old_live_and_same_step_floor_match_original -- --ignored --nocapture
  gdformat spikes/rust-stack/oracle/post_dead_body.gd
  gdlint spikes/rust-stack/oracle/post_dead_body.gd
  "$GODOT" --headless --path . --script spikes/rust-stack/oracle/post_dead_body.gd -- "$CORE_FIXTURE_LEVEL" "$CORE_FIXTURE_INPUT" "$CORE_FIXTURE_DIR" 2>&1 | tee "$CORE_FIXTURE_DIR/dead-body.log"
  if grep -E 'SCRIPT ERROR|ERROR:' "$CORE_FIXTURE_DIR/dead-body.log"; then exit 1; fi
  grep POST_DEAD_BODY_BOUNDARY_ORACLE_DONE "$CORE_FIXTURE_DIR/dead-body.log"
fi
cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --lib
cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test fixture_parity -- --ignored --nocapture
if [[ "$fixture" == stilts_target ]]; then cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test runtime_boundary -- --ignored --nocapture; fi
if [[ "$fixture" == checkpoint_target ]]; then cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test checkpoint_boundary -- --ignored --nocapture; fi
if [[ "$fixture" == posts_target.pound ]]; then cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test post_boundary -- --ignored --nocapture; fi
GODOT=${GODOT:-godot}
[[ $("$GODOT" --version) == 4.7.2.* ]]
branches=(1 6 11 70 75 90 160 220 350)
if [[ "$fixture" == actors_target ]]; then branches+=(780 790 791 1000 1080 1100 1200); fi
if [[ "$fixture" == stilts_target ]]; then branches+=(106 107 108 244 245 246); fi
if [[ "$fixture" == stilts_target.knock ]]; then branches+=(25 26 27 77 78 79); fi
if [[ "$fixture" == checkpoint_target ]]; then branches+=(52 53 54 58 59 60 112 113 114 157 158 159 1333 1334 1335 1573 1574 1575 1634 1635 1636 1637 1638 1639 174 175 176 1672 1673 1674); fi
if [[ "$fixture" == posts_target.duck ]]; then branches+=(80 81 82 89 90 91 100 101 102); fi
if [[ "$fixture" == posts_target ]]; then branches+=(53 54 55 198 199 200); fi
if [[ "$fixture" == posts_target.pound ]]; then branches+=(53 54 55 80 81 82 142 143 144 152 153 154 214 215 216 224 225 226 92 93 94 116 117 118 120 121 122 164 165 166 188 189 190 192 193 194 236 237 238 260 261 262 264 265 266 286 287 288); fi
mapfile -t branches < <(printf '%s\n' "${branches[@]}" | sort -nu)
for tick in "${branches[@]}"; do
  "$GODOT" --headless --path . --script spikes/rust-stack/oracle/continue.gd -- "$CORE_FIXTURE_LEVEL" "$CORE_FIXTURE_INPUT" "$CORE_FIXTURE_DIR/snapshots.v10.stream" "$CORE_FIXTURE_DIR/rust-uninterrupted-$tick.v10" "$tick" 2>&1 | tee "$CORE_FIXTURE_DIR/b-to-a-$tick.log"
  if grep -E 'SCRIPT ERROR|ERROR:' "$CORE_FIXTURE_DIR/b-to-a-$tick.log"; then exit 1; fi
  grep B_TO_A_CONTINUATION_DONE "$CORE_FIXTURE_DIR/b-to-a-$tick.log"
done
cargo clippy --locked --manifest-path spikes/rust-stack/core/Cargo.toml --all-targets -- -D warnings
shellcheck -s bash spikes/rust-stack/oracle/fixture.sh
printf 'NEXT_FIXTURE_DONE source=%s fixture=%s api=VisualState.scale_optional_ratio target_admission=refused\n' "$(git rev-parse HEAD)" "$fixture"
