#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
# aka only. Usage: pack_parity.sh SWEEP_TAG [TICKS] [LIMIT] [SKIP]
# SKIP: leave out the first SKIP admitted levels (shards across aka trees).
# Every-tick Godot parity on each admitted corpus level of pack-sweep-SWEEP_TAG.jsonl, on
# a generic walk-and-hop route (no state edits). Prints one PACK_PARITY line per level
# and a PACK_PARITY_DONE summary. Private levels and streams stay under artifacts.
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
git diff --exit-code 297ada9a022d0ddc297dd2d4091c5dccfab4531e -- src tests/fixtures
tag=$1
ticks=${2:-900}
limit=${3:-100000}
skip=${4:-0}
root="$HOME/eggshell-remote/artifacts/full-rust-ab"
sweep="$root/speed/pack-sweep-$tag.jsonl"
corpus="$HOME/.local/share/eggshell-run/corpus/levels"
# Per aka tree: lanes run pack parity concurrently on one host.
out="$root/core/pack-parity-$(basename "$PWD")"
mkdir -p "$out"
chmod 700 "$out"
GODOT=$(command -v "${GODOT:-godot}")
[[ $("$GODOT" --version) == 4.7.2.* ]]
"$GODOT" --headless --path . --editor --import >"$out/import.log" 2>&1
input="$out/route-$ticks.input.json"
# Walk right, hop every cycle, lick and pause: reaches objects past the start.
python3 -c "
import json, sys
n = int(sys.argv[1])
cycle = [2] * 40 + [6] * 14 + [2] * 20 + [8] + [0] * 12 + [2] * 30 + [0] * 8
print(json.dumps((cycle * (n // len(cycle) + 1))[:n]))
" "$ticks" > "$input"
cargo test --locked --release --manifest-path spikes/rust-stack/core/Cargo.toml --test fixture_parity --no-run >"$out/build.log" 2>&1
pass=0
fail=0
count=0
while IFS= read -r id; do
  count=$((count + 1))
  [[ $count -gt $skip ]] || continue
  [[ $((count - skip)) -le $limit ]] || break
  dir="$out/$id"
  rm -rf "$dir"
  # A Godot that printed ORACLE_DONE can hang on exit, so bound the run and judge the
  # export by its log, not its exit status.
  timeout 900 "$GODOT" --headless --path . --script spikes/rust-stack/oracle/export.gd -- "$corpus/$id.json" "$input" "$dir" >"$out/$id.export.log" 2>&1 || true
  if ! grep -q 'ORACLE_DONE' "$out/$id.export.log" \
    || grep -qE 'SCRIPT ERROR|ERROR:|ORACLE_FAILED' "$out/$id.export.log"; then
    printf 'PACK_PARITY id=%s result=export-failed\n' "$id"
    fail=$((fail + 1))
    continue
  fi
  if CORE_FIXTURE=corpus CORE_FIXTURE_DIR="$dir" CORE_FIXTURE_LEVEL="$corpus/$id.json" CORE_FIXTURE_INPUT="$input" \
    cargo test --locked --release --manifest-path spikes/rust-stack/core/Cargo.toml --test fixture_parity \
    admitted_fixture_has_uninterrupted_every_tick_parity -- --ignored --nocapture >"$out/$id.test.log" 2>&1; then
    printf 'PACK_PARITY id=%s result=pass\n' "$id"
    pass=$((pass + 1))
  else
    reason=$(grep -m1 -oE 'mismatch tick=[0-9]+: .{0,220}|next [a-z/ ]+gate at [^\n]{0,200}' "$out/$id.test.log" || echo unknown)
    printf 'PACK_PARITY id=%s result=fail %s\n' "$id" "$reason"
    fail=$((fail + 1))
  fi
done < <(grep '"status":"ok"' "$sweep" | sed 's/.*"id":"\([^"]*\)".*/\1/')
printf 'PACK_PARITY_DONE tag=%s ticks=%s pass=%s fail=%s\n' "$tag" "$ticks" "$pass" "$fail"
