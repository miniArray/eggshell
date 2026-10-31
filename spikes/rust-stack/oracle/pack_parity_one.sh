#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
# aka only. Usage: pack_parity_one.sh CORPUS_ID [TICKS]
# Reruns pack_parity.sh's export and every-tick test for one corpus level, in the same
# per-tree output directory (run pack_parity.sh once first for the route input).
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
id=$1
ticks=${2:-900}
out="$HOME/eggshell-remote/artifacts/full-rust-ab/core/pack-parity-$(basename "$PWD")"
corpus="$HOME/.local/share/eggshell-run/corpus/levels"
input="$out/route-$ticks.input.json"
dir="$out/$id"
GODOT=$(command -v "${GODOT:-godot}")
rm -rf "$dir"
timeout 900 "$GODOT" --headless --path . --script spikes/rust-stack/oracle/export.gd -- "$corpus/$id.json" "$input" "$dir" >"$out/$id.export.log" 2>&1 || true
if ! grep -q 'ORACLE_DONE' "$out/$id.export.log" || grep -qE 'SCRIPT ERROR|ERROR:|ORACLE_FAILED' "$out/$id.export.log"; then
  printf 'PACK_PARITY id=%s result=export-failed\n' "$id"
  exit 1
fi
if CORE_FIXTURE=corpus CORE_FIXTURE_DIR="$dir" CORE_FIXTURE_LEVEL="$corpus/$id.json" CORE_FIXTURE_INPUT="$input" \
  cargo test --locked --release --manifest-path spikes/rust-stack/core/Cargo.toml --test fixture_parity \
  admitted_fixture_has_uninterrupted_every_tick_parity -- --ignored --nocapture >"$out/$id.test.log" 2>&1; then
  printf 'PACK_PARITY id=%s result=pass\n' "$id"
else
  reason=$(grep -m1 -oE 'mismatch tick=[0-9]+: .{0,220}|next [a-z/ ]+gate at [^\n]{0,200}' "$out/$id.test.log" || echo unknown)
  printf 'PACK_PARITY id=%s result=fail %s\n' "$id" "$reason"
  exit 1
fi
