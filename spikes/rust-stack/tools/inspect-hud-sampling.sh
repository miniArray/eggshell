#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix
# Source-only inspection; no GPU cause/fix inferred from declarations.
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
SRC=$(nix build --impure --no-link --print-out-paths --expr 'let f=builtins.getFlake (toString ./.); in f.inputs.nixpkgs.legacyPackages.x86_64-linux.godot.src')
printf 'GODOT_HUD_RECT_PRIMARY %s\n' "$SRC"
sha256sum "$SRC/drivers/gles3/shaders/canvas.glsl" "$SRC/drivers/gles3/rasterizer_canvas_gles3.cpp"
printf '\nFULL_CANVAS_VERTEX_SHADER\n'
sed -n '1,345p' "$SRC/drivers/gles3/shaders/canvas.glsl"
printf '\nCANVAS_FRAGMENT_UV_TEXTURE_CONTEXT\n'
grep -n -A20 -B10 'uv_interp\|pixel_size\|textureLod\|texture2D\|texture(color_texture' "$SRC/drivers/gles3/shaders/canvas.glsl"
printf '\nBATCH_RECT_PROJECTION_UV_IMPLEMENTATION\n'
grep -n -A22 -B14 'projection_matrix\|projection.*columns\|source_rect\|src_rect\|dst_rect\|CLIP_UV\|USE_PIXEL_SNAP' "$SRC/drivers/gles3/rasterizer_canvas_gles3.cpp"
printf '\nSCREEN_TRANSFORM_AND_PIXEL_SNAP_CONFIGURATION\n'
grep -n -A40 -B14 'screen_transform\|use_pixel_snap\|p_snap_2d_vertices_to_pixel' "$SRC/drivers/gles3/rasterizer_canvas_gles3.cpp"
grep -n -A8 -B6 'snap_2d_vertices_to_pixel\|snap_2d_transforms_to_pixel' "$SRC/scene/main/viewport.cpp" "$SRC/scene/main/viewport.h" "$SRC/servers/rendering/renderer_viewport.cpp"
printf '\nORIGINAL_PROJECT_CONFIGURATION\n'
cat project.godot
printf '\nORIGINAL_HUD_DRAWING\n'
sed -n '320,382p' src/view/hud.gd
