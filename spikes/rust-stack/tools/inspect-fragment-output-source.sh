#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix
# Public primary sources only; no GPU verdict is inferred from declarations.
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
SPEC="$HOME/eggshell-remote/artifacts/full-rust-ab/glsl-es-1.00-public-spec/spec.txt"
[[ -f "$SPEC" ]]
printf 'PRIMARY_ESSL100_FRAGMENT_BUILTINS %s\n' "$SPEC"
grep -n -A8 -B8 -E '(lowp|mediump|highp).*gl_FragColor|fragment output precision|gl_FragColor.*precision' "$SPEC"
SRC=$(nix build --impure --no-link --print-out-paths --expr 'let f=builtins.getFlake (toString ./.); in f.inputs.nixpkgs.legacyPackages.x86_64-linux.godot.src')
printf 'PRIMARY_GODOT_472_FRAGMENT_OUTPUT %s\n' "$SRC"
grep -n -A5 -B5 'out vec4 frag_color\|precision highp float' "$SRC/drivers/gles3/shaders/canvas.glsl" "$SRC/drivers/gles3/shader_gles3.cpp"
printf 'PRIMARY_GODOT_TEXTURE_READBACK\n'
grep -n -A14 -B10 'glReadPixels\|p_texture->format != Image::FORMAT_RGBA8' "$SRC/drivers/gles3/storage/texture_storage.cpp"
