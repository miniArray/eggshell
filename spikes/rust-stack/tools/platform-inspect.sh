#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils git nix
set -euo pipefail
export NIX_CONFIG='builders ='
test "$(hostname)" = aka
printf 'NIX_CONFIG=%s\n' "$NIX_CONFIG"
nix config show | grep '^builders ='
nix eval --impure --raw --expr 'let f = builtins.getFlake (toString ./.); p = import f.inputs.nixpkgs {system="x86_64-linux";}; in p.path'
printf '\n'
ls -l "$HOME/.local/share/eggshell/packs/original-v3-final"
head -c 16000 "$HOME/.local/share/eggshell/packs/original-v3-final/manifest.json"
printf '\n'
