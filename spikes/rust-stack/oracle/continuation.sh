#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
git diff --exit-code 297ada9a022d0ddc297dd2d4091c5dccfab4531e -- src tests/fixtures
GODOT=${GODOT:-godot}
[[ $("$GODOT" --version) == 4.7.2.* ]]
root="$HOME/eggshell-remote/artifacts/full-rust-ab/core/stride-4.7.2"
printf 'CONTINUATION_SOURCE %s\n' "$(git rev-parse HEAD)"
sha256sum "$root/rust-uninterrupted-120.v10" "$root/snapshots.v10.stream"
"$GODOT" --headless --path . --script spikes/rust-stack/oracle/continue.gd -- "$PWD/tests/fixtures/stride.level.json" "$PWD/tests/fixtures/stride.input.json" "$root/snapshots.v10.stream" "$root/rust-uninterrupted-120.v10" 120 2>&1 | tee "$root/b-to-a.log"
if grep -E 'SCRIPT ERROR|ERROR:' "$root/b-to-a.log"; then exit 1; fi
grep B_TO_A_CONTINUATION_DONE "$root/b-to-a.log"
