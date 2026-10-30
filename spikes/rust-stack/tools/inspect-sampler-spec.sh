#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils curl poppler-utils
# Public Khronos primary specification; never sends private application data.
set -euo pipefail
[[ $(hostname) == aka ]]
OUT="$HOME/eggshell-remote/artifacts/full-rust-ab/glsl-es-1.00-public-spec"
mkdir -p "$OUT"
curl --fail --silent --show-error \
  https://registry.khronos.org/OpenGL/specs/es/2.0/GLSL_ES_Specification_1.00.pdf -o "$OUT/spec.pdf"
pdftotext -layout "$OUT/spec.pdf" "$OUT/spec.txt"
grep -n -A18 -B5 'precision lowp sampler2D\|The precision of the return type\|precision of the sampler\|precision qualifier of the sampler' "$OUT/spec.txt"
sha256sum "$OUT/spec.pdf"
