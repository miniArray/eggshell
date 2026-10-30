#!/run/current-system/sw/bin/bash
# Copied to the private bundle root; parent exclusively runs this on Pro.
set -euo pipefail
unset LD_LIBRARY_PATH
ROOT=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)
declare +x LIBPATH="$ROOT/lib:/run/opengl-driver/lib"
export XKB_CONFIG_ROOT="$ROOT/xkb"
if [[ -f "$ROOT/locale/en_US.UTF-8/Compose" ]]; then
  export XLOCALEDIR="$ROOT/locale"
  export XCOMPOSEFILE="$ROOT/locale/en_US.UTF-8/Compose"
fi
export SDL_VIDEODRIVER=wayland SDL_AUDIODRIVER=dummy SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=0
counts=(25 50 100 200 400)
modes=(uncapped realtime)
if [[ $# -ne 0 ]]; then
  [[ $# -eq 2 ]]
  case "$1" in 25|50|100|200|400) counts=("$1");; *) exit 2;; esac
  case "$2" in uncapped|realtime) modes=("$2");; *) exit 2;; esac
fi
mkdir -p "$ROOT/data"
runs=0
for mode in "${modes[@]}"; do
  for n in "${counts[@]}"; do
    save="$ROOT/data/scaling-$n-$mode-saves"
    mkdir "$save" # fail on reuse; every measurement gets a fresh startup maps file.
    flags=()
    if [[ "$mode" == uncapped ]]; then flags+=(--uncapped); fi
    printf 'OWNED_SCALING_BEGIN benchmark_unverified_level=true N=%s mode=%s input_calls=1200 hint_only=true\n' "$n" "$mode"
    "$ROOT/lib/ld-linux-aarch64.so.1" --library-path "$LIBPATH" "$ROOT/bin/eggshell-spike-player" --play \
      --benchmark-unverified-level --level "$ROOT/private-input/scale-$n.level.json" \
      --collision "$ROOT/private-input/collision_table.json" --schema "$ROOT/private-input/schema.json" \
      --pack-root "$ROOT/private-pack" --pack-inventory "$ROOT/private-pack/pack-files.sha256.json" \
      --view-metrics "$ROOT/private-input/view-metrics.json" --replay "$ROOT/private-input/idle-1200.input.json" \
      --ticks 1200 --seconds 120 --save-dir "$save" "${flags[@]}" 2>&1 |
      while IFS= read -r line; do printf 'benchmark_unverified_level=true N=%s mode=%s %s\n' "$n" "$mode" "$line"; done
    runs=$((runs+1))
    printf 'OWNED_SCALING_CASE_DONE benchmark_unverified_level=true N=%s mode=%s\n' "$n" "$mode"
  done
done
printf 'OWNED_SCALING_DONE benchmark_unverified_level=true runs=%s hint_only=true target_claim=false FPS_claim=false\n' "$runs"
