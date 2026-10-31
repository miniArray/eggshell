#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
# aka only, diagnosis. Usage: [PACK_TREE=AKA_TREE] corpus_dump.sh CORPUS_ID FIRST LAST
# Per-tick Rust player fields for a pack parity level (run pack_parity.sh first).
set -euo pipefail
[[ $(hostname) == aka ]]
out="$HOME/eggshell-remote/artifacts/full-rust-ab/core/pack-parity-${PACK_TREE:-$(basename "$PWD")}"
export CORE_FIXTURE=corpus
export CORE_FIXTURE_DIR="$out/$1"
export CORE_FIXTURE_INPUT="$out/route-900.input.json"
export CORE_FIXTURE_LEVEL="$HOME/.local/share/eggshell-run/corpus/levels/$1.json"
export FIXTURE_DUMP=1
cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test fixture_parity admitted_fixture_has_uninterrupted_every_tick_parity -- --ignored --nocapture 2>&1 \
  | grep -E '^DUMP|mismatch' | awk -v a="$2" -v b="$3" '/mismatch/ {print; next} {split($2,t,"="); if (t[2]>=a && t[2]<=b) print}'
