#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
# aka only. Usage: dump_fixture.sh FIXTURE FIRST LAST
# Per-tick player fields of an already exported fixture (Rust run; it matches Godot when parity passes).
set -euo pipefail
[[ $(hostname) == aka ]]
fixture=$1
base=${fixture%%.*}
export CORE_FIXTURE="$fixture"
export CORE_FIXTURE_DIR="$HOME/eggshell-remote/artifacts/full-rust-ab/core/$fixture-4.7.2"
export CORE_FIXTURE_INPUT="$HOME/eggshell-remote/artifacts/full-rust-ab/core/$fixture.input.json"
export CORE_FIXTURE_LEVEL="$PWD/tests/fixtures/$base.level.json"
if [[ -f "$PWD/spikes/rust-stack/core/tests/fixtures/$base.level.json" ]]; then export CORE_FIXTURE_LEVEL="$PWD/spikes/rust-stack/core/tests/fixtures/$base.level.json"; fi
export FIXTURE_DUMP=1
cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --test fixture_parity admitted_fixture_has_uninterrupted_every_tick_parity -- --ignored --nocapture 2>&1 \
  | grep '^DUMP' | awk -v a="$2" -v b="$3" '{split($2,t,"="); if (t[2]>=a && t[2]<=b) print}'
