#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix
# Read the exact vendor copy/readback path; no private data or GPU claims.
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
SRC=$(nix build --impure --no-link --print-out-paths --expr 'let f=builtins.getFlake (toString ./.); in f.inputs.nixpkgs.legacyPackages.x86_64-linux.godot.src')
printf 'GODOT_COPY_PRIMARY_SOURCE %s\n' "$SRC"
sha256sum "$SRC/drivers/gles3/effects/copy_effects.cpp" "$SRC/drivers/gles3/shaders/effects/copy.glsl" "$SRC/drivers/gles3/storage/texture_storage.cpp"
printf '\nFULL_COPY_SHADER\n'
cat "$SRC/drivers/gles3/shaders/effects/copy.glsl"
printf '\nCOPY_QUAD_INITIALIZATION\n'
sed -n '35,110p' "$SRC/drivers/gles3/effects/copy_effects.cpp"
grep -n -A8 -B3 'draw_screen_quad\|p_linear_to_srgb = ' "$SRC/drivers/gles3/effects/copy_effects.h"
printf '\nCOPY_TO_RECT_IMPLEMENTATION\n'
grep -n -A65 -B10 'void CopyEffects::copy_to_rect' "$SRC/drivers/gles3/effects/copy_effects.cpp"
printf '\nREADBACK_AND_TARGET_FILTER_CONTEXT\n'
sed -n '1515,1632p' "$SRC/drivers/gles3/storage/texture_storage.cpp"
sed -n '2540,2655p' "$SRC/drivers/gles3/storage/texture_storage.cpp"
