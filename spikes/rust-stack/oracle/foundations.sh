#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
git diff --exit-code 297ada9a022d0ddc297dd2d4091c5dccfab4531e -- src tests/fixtures
GODOT=${GODOT:-godot}
[[ $("$GODOT" --version) == 4.7.2.* ]]
export CORE_PROOF_DIR="$HOME/eggshell-remote/artifacts/full-rust-ab/core/foundations"
mkdir -p "$CORE_PROOF_DIR"
chmod 700 "$CORE_PROOF_DIR"
"$GODOT" --headless --path . --script spikes/rust-stack/oracle/primitives.gd -- "$CORE_PROOF_DIR/primitives.json" 2>&1 | tee "$CORE_PROOF_DIR/primitives.log"
if grep -E 'SCRIPT ERROR|ERROR:' "$CORE_PROOF_DIR/primitives.log"; then exit 1; fi
grep PRIMITIVE_ORACLE_DONE "$CORE_PROOF_DIR/primitives.log"
"$GODOT" --headless --path . --script spikes/rust-stack/oracle/world_proof.gd -- "$HOME/.local/share/eggshell-run/corpus/levels/6600ab52a3bb0805d316b9f1.json" "$CORE_PROOF_DIR/world.json" 2>&1 | tee "$CORE_PROOF_DIR/world.log"
if grep -E 'SCRIPT ERROR|ERROR:' "$CORE_PROOF_DIR/world.log"; then exit 1; fi
grep WORLD_ORACLE_DONE "$CORE_PROOF_DIR/world.log"
export CORE_ORACLE_DIR="$HOME/eggshell-remote/artifacts/full-rust-ab/core/stride-4.7.2"
nix-shell spikes/rust-stack/core/check.sh
printf 'FOUNDATIONS_CHECK_DONE\n'
