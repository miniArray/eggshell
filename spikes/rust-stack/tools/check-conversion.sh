#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix
# aka only. The conversion gate: format, core + player tests and lints, every Godot
# parity check, and the Rust trace against a recorded baseline on the 9 benchmark levels.
# Usage: check-conversion.sh TAG [BASELINE_TAG]
set -uo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]] || exit 1
TAG=$1
BASE=${2:-names-2333d44}  # same states as baseline-d34a350; image names instead of bind indices
failed=0
step() {
  local name=$1
  shift
  if "$@" >"/tmp/conversion-$name.log" 2>&1; then
    printf 'GATE_PASS %s\n' "$name"
  else
    failed=$((failed + 1))
    printf 'GATE_FAIL %s\n' "$name"
    grep -E '^error|^warning|panicked|FAILED|-->|PARITY_FAIL|expected|differ|^[<>] ' "/tmp/conversion-$name.log" | head -30
  fi
}
rust() { nix develop ./spikes/rust-stack/player -c "$@"; }
rust cargo fmt --manifest-path spikes/rust-stack/core/Cargo.toml
rust cargo fmt --manifest-path spikes/rust-stack/player/Cargo.toml
step core-test rust cargo test --release --manifest-path spikes/rust-stack/core/Cargo.toml
step core-clippy rust cargo clippy --manifest-path spikes/rust-stack/core/Cargo.toml --lib --tests -- -D warnings
step player-test rust cargo test --manifest-path spikes/rust-stack/player/Cargo.toml --lib --features benchmark-work-counters
step player-clippy rust cargo clippy --manifest-path spikes/rust-stack/player/Cargo.toml --features benchmark-work-counters --all-targets -- -D warnings
step godot-parity nix-shell spikes/rust-stack/oracle/parity_all.sh
export REAL_SCREENS_DIR=real-screens-v3
export TRACE_LEVELS="real-64d3d5f1d77b3fe14198c693 real-6aa65f0c574012395a0faddf real-66476d1f0e6c18cafbaaf355 real-6600ab52a3bb0805d316b9f1 real-64625273d4802b03e9cd98d2 real-69ef3bb076aa6bf9fc85b8bb real-686904f725e59f7ef841ddba real-6a436c973e11434283469b06 real-6a737f7064c334870404d4e0 scale-2400"
step rust-trace nix-shell spikes/rust-stack/tools/trace-equality.sh "$TAG" "$BASE"
printf 'CONVERSION_GATE_DONE tag=%s failed=%s source=%s\n' "$TAG" "$failed" "$(git rev-parse HEAD)"
[[ "$failed" == 0 ]]
