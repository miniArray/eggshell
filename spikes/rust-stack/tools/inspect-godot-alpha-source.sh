#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix curl
# Public vendor source matching the actual pinned Godot package, not a summary.
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
ROOT=$PWD
SRC=$(nix build --impure --no-link --print-out-paths --expr 'let f=builtins.getFlake (toString ./.); in f.inputs.nixpkgs.legacyPackages.x86_64-linux.godot.src')
printf 'GODOT_PRIMARY_SOURCE %s\n' "$SRC"
head -n 18 "$SRC/version.py"
for file in drivers/gles3/shaders/canvas.glsl drivers/gles3/rasterizer_canvas_gles3.cpp drivers/gles3/shader_gles3.cpp; do
  printf '\nPRIMARY_FILE %s\n' "$file"
  sha256sum "$SRC/$file"
  grep -n -E 'precision|lowp|mediump|color_interp|color_texture|modulat|SRC_ALPHA|DITHER|blend_func|blendFunc|to_abgr|packUnorm|pack_unorm' "$SRC/$file"
done
cd "$ROOT"
