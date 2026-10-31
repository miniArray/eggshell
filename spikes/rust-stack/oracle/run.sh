#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
git diff --exit-code 297ada9a022d0ddc297dd2d4091c5dccfab4531e -- src tests/fixtures
out="$HOME/eggshell-remote/artifacts/full-rust-ab/core"
mkdir -p "$out"
chmod 700 "$out"
printf 'ORACLE_ENV host=%s NIX_CONFIG=%s source=%s\n' "$(hostname)" "$NIX_CONFIG" "$(git rev-parse HEAD)"
GODOT=$(command -v "${GODOT:-godot}")
version=$("$GODOT" --version)
[[ "$version" == 4.7.2.* ]] || { printf 'Expected reference Godot 4.7.2, got %s\n' "$version" >&2; exit 1; }
printf 'ORACLE_GODOT executable=%s version=%s\n' "$(command -v "$GODOT")" "$version"
project=.
if [[ "${ORACLE_OVERLAY:-0}" == 1 ]]; then
  project="$out/counter-overlay"
  python3 spikes/rust-stack/oracle/instrument.py "$project"
fi
sha256sum "$GODOT" spikes/rust-stack/oracle/export.gd spikes/rust-stack/oracle/instrument.py
"$GODOT" --headless --path "$project" --editor --import >"$out/import-4.7.2.log" 2>&1
if grep -E 'SCRIPT ERROR|Parse Error|Compile Error|ERROR:' "$out/import-4.7.2.log"; then exit 1; fi
fixture=${1:-stride}
if [[ "$fixture" == target ]]; then
  python3 spikes/rust-stack/oracle/target_route.py "$out/target.input.json"
  level="$HOME/.local/share/eggshell-run/corpus/levels/6600ab52a3bb0805d316b9f1.json"
  input="$out/target.input.json"
elif [[ "$fixture" == actors_target || "$fixture" == stilts_target || "$fixture" == stilts_target.knock || "$fixture" == checkpoint_target || "${fixture%%.*}" == posts_target || "$fixture" == blocks_target || "$fixture" == spans_target || "$fixture" == flats_target || "$fixture" == hards_target || "$fixture" == falls_target || "$fixture" == grows_target || "$fixture" == gates_target || "$fixture" == ledges_target || "$fixture" == stems_target || "$fixture" == flowers_target || "$fixture" == switches_target || "$fixture" == shells_target || "$fixture" == armored_target || "$fixture" == spears_target || "$fixture" == lifts_target || "$fixture" == snowflow_target || "$fixture" == fish_target || "$fixture" == melons_target || "$fixture" == thieves_target || "$fixture" == rollers_target || "$fixture" == shooters_target || "$fixture" == wings_target || "$fixture" == launchers_target || "$fixture" == sprouts_target || "$fixture" == jugglers_target || "$fixture" == bulks_target || "$fixture" == gusts_target || "$fixture" == hounds_target || "$fixture" == spores_target || "$fixture" == hangs_target || "$fixture" == eggblocks_target || "$fixture" == pillars_target || "$fixture" == balloons_target ]]; then
  python3 spikes/rust-stack/oracle/normal_routes.py "$fixture" "$out/$fixture.input.json"
  level="$PWD/spikes/rust-stack/core/tests/fixtures/${fixture%%.*}.level.json"
  input="$out/$fixture.input.json"
elif [[ "$fixture" == collections ]]; then
  python3 spikes/rust-stack/oracle/normal_routes.py "$fixture" "$out/$fixture.input.json"
  level="$PWD/spikes/rust-stack/core/tests/fixtures/collections.level.json"
  input="$out/$fixture.input.json"
elif [[ "$fixture" == bounce.pad || "$fixture" == bounce.moves || "$fixture" == stride.eat ]]; then
  python3 spikes/rust-stack/oracle/normal_routes.py "$fixture" "$out/$fixture.input.json"
  level="$PWD/tests/fixtures/${fixture%%.*}.level.json"
  input="$out/$fixture.input.json"
elif [[ "$fixture" == stride.damage ]]; then
  level="$PWD/tests/fixtures/stride.level.json"
  input="$PWD/tests/fixtures/stride.damage.input.json"
else
  level="$PWD/tests/fixtures/$fixture.level.json"
  input="$PWD/tests/fixtures/$fixture.input.json"
fi
suffix=4.7.2
if [[ "${ORACLE_OVERLAY:-0}" == 1 ]]; then suffix=4.7.2-counters; fi
"$GODOT" --headless --path "$project" --script spikes/rust-stack/oracle/export.gd -- "$level" "$input" "$out/$fixture-$suffix" 2>&1 | tee "$out/$fixture-$suffix.log"
if grep -E 'SCRIPT ERROR|Parse Error|Compile Error|ERROR:|ORACLE_FAILED' "$out/$fixture-$suffix.log"; then exit 1; fi
grep 'ORACLE_DONE' "$out/$fixture-$suffix.log"
printf 'ORACLE_RUN_DONE fixture=%s\n' "$fixture"
