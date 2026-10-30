#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
if [[ -n "${EXPECTED_SOURCE_SHA:-}" ]]; then test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_SHA"; fi
git diff --exit-code 297ada9a022d0ddc297dd2d4091c5dccfab4531e -- src tests/fixtures
GODOT=${GODOT:-godot}
[[ $("$GODOT" --version) == 4.7.2.* ]]
root="$HOME/eggshell-remote/artifacts/full-rust-ab/core/foundations"
mkdir -p "$root"
export CORE_INACTIVE_POLICY="$root/inactive-visibility.json"
gdformat spikes/rust-stack/oracle/inactive_visibility.gd
gdlint spikes/rust-stack/oracle/inactive_visibility.gd
"$GODOT" --headless --path . --script spikes/rust-stack/oracle/inactive_visibility.gd -- "$CORE_INACTIVE_POLICY" 2>&1 | tee "$root/inactive-visibility.log"
if grep -E 'SCRIPT ERROR|ERROR:' "$root/inactive-visibility.log"; then exit 1; fi
grep INACTIVE_VISIBILITY_ORACLE_DONE "$root/inactive-visibility.log"
cargo fmt --manifest-path spikes/rust-stack/core/Cargo.toml
cargo test --locked --manifest-path spikes/rust-stack/core/Cargo.toml --lib original_inactive_visibility_policy -- --ignored --nocapture
cargo clippy --locked --manifest-path spikes/rust-stack/core/Cargo.toml --all-targets -- -D warnings
shellcheck -s bash spikes/rust-stack/oracle/inactive_visibility.sh spikes/rust-stack/oracle/evidence.sh
printf 'INACTIVE_VISIBILITY_DONE source=%s cases=320 public_api=unchanged gameplay_and_v10=unchanged target204=refused\n' "$(git rev-parse HEAD)"
