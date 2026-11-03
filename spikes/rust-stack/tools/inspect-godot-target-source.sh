#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix
# Exact locked public vendor source, not a claim about observed attachment state.
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
SRC=$(nix build --impure --no-link --print-out-paths --expr 'let f=builtins.getFlake (toString ./.); in f.inputs.nixpkgs.legacyPackages.x86_64-linux.godot.src')
printf 'GODOT_TARGET_PRIMARY_SOURCE %s\n' "$SRC"
for file in drivers/gles3/storage/texture_storage.cpp drivers/gles3/rasterizer_gles3.cpp; do
  sha256sum "$SRC/$file"
  set +e
  grep -n -A12 -B8 -E 'glReadPixels|glDisable\(GL_DITHER\)|color_internal_format =|GL_RGBA16F|GL_RGBA8;' "$SRC/$file"
  status=$?
  set -e
  [[ "$status" -le 1 ]]
done
