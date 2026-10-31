#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
# aka only. Usage: pack-sweep.sh TAG. Strict load + 600 idle steps + save/restore for every
# corpus level; writes speed/pack-sweep-TAG.jsonl and prints the counts.
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
OUT="$HOME/eggshell-remote/artifacts/full-rust-ab/speed/pack-sweep-$1.jsonl"
PACK_SWEEP_OUT="$OUT" cargo test --locked --release --manifest-path spikes/rust-stack/core/Cargo.toml \
  --test pack_sweep -- --ignored --nocapture 2>&1 | grep -E 'PACK_SWEEP_DONE|panicked|test result'
printf 'PACK_SWEEP_FILE %s\n' "$OUT"
