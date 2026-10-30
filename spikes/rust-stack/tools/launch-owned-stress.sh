#!/run/current-system/sw/bin/bash
# Benchmark-only private bundle entry. Parent exclusively operates the Pro.
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
mode=${1:?usage: launch-owned-stress zoom LEVEL | crowd | sustained LEVEL ZOOM}
shift
variant=normal
picture_invalid=false
normalize_level() {
  level=${1%.level.json}
  case "$level" in real-*) [[ "$level" =~ ^real-[0-9a-f]{24}$ ]] || exit 2;; scale-25|scale-50|scale-100|scale-200|scale-400|scale-1600|scale-2400|scale-400-dark|mix-500|mix-2000|mix-500-dark|wide-400-dark) ;; *) printf 'Unknown stress level: %s\n' "$level" >&2; exit 2;; esac
}
app() { "$ROOT/lib/ld-linux-aarch64.so.1" --library-path "$LIBPATH" "$ROOT/bin/eggshell-spike-player" "$@"; }
prefix() { local fidelity=not_claimed; [[ "$level" != real-* ]] || fidelity=false; while IFS= read -r line; do printf 'benchmark_unverified_level=true mode=%s level=%s zoom=%s variant=%s picture_invalid=%s faithful_real_level=%s %s\n' "$mode" "$level" "$zoom" "$variant" "$picture_invalid" "$fidelity" "$line"; done; }
sensors() {
  local phase=$1 path
  printf 'STRESS_SENSORS phase=%s\n' "$phase"
  shopt -s nullglob
  for path in /sys/class/thermal/thermal_zone*/temp /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq /sys/class/devfreq/*/cur_freq; do
    if [[ -r "$path" ]]; then printf '%s=' "$path"; cat "$path" || true; fi
  done
}
run_case() {
  local calls=$1 cadence=$2 save
  local flags=()
  if [[ "$cadence" == uncapped ]]; then flags+=(--uncapped); else flags+=(--presentation-feedback); fi
  picture_invalid=false
  if [[ "$level" == real-* ]]; then flags+=(--benchmark-real-screen); fi
  if [[ "$variant" == single-texture ]]; then flags+=(--benchmark-single-texture); picture_invalid=true; fi
  if [[ "$variant" == atlas ]]; then flags+=(--atlas); fi
  if [[ "$variant" == pipeline ]]; then flags+=(--atlas --pipeline); fi
  if [[ -n "${digest_every:-}" ]]; then
    local dump="$ROOT/data/digest-$level-zoom-$zoom-$variant"
    mkdir "$dump"
    flags+=(--frame-digest-every "$digest_every" --frame-dump-dir "$dump")
  fi
  save="$ROOT/data/stress-$mode-$level-zoom-$zoom-$variant-saves"
  mkdir "$save"
  printf 'OWNED_STRESS_BEGIN mode=%s level=%s zoom=%s calls=%s saves_disabled=true\n' "$mode" "$level" "$zoom" "$calls" | prefix
  app --play --benchmark-unverified-level --zoom "$zoom" \
    --level "$ROOT/private-input/$level.level.json" --collision "$ROOT/private-input/collision_table.json" \
    --schema "$ROOT/private-input/schema.json" --pack-root "$ROOT/private-pack" \
    --pack-inventory "$ROOT/private-pack/pack-files.sha256.json" --view-metrics "$ROOT/private-input/view-metrics.json" \
    --replay "$ROOT/private-input/idle-$calls.input.json" --ticks "$calls" --seconds 900 --save-dir "$save" "${flags[@]}" 2>&1 | prefix
}
mkdir -p "$ROOT/data"
case "$mode" in
  zoom)
    [[ $# -eq 1 ]]; normalize_level "$1"
    query_flags=(); [[ "$level" != real-* ]] || query_flags+=(real-screen)
    read -r tag zoom_min zoom_max < <(app --benchmark-zoom-range "$ROOT/private-input/$level.level.json" "$ROOT/private-input/collision_table.json" "${query_flags[@]}")
    [[ "$tag" == RUST_ZOOM_RANGE ]]
    for ((zoom=zoom_min; zoom<=zoom_max; zoom++)); do
      for variant in normal atlas pipeline; do run_case 600 uncapped; done
    done
    printf 'OWNED_STRESS_ZOOM_DONE level=%s zoom_min=%s zoom_max=%s benchmark_unverified_level=true\n' "$level" "$zoom_min" "$zoom_max"
    ;;
  atlas-check)
    # Picture check: the atlas must give byte-identical frames. Not a timing run.
    [[ $# -eq 1 ]]; normalize_level "$1"
    query_flags=(); [[ "$level" != real-* ]] || query_flags+=(real-screen)
    read -r tag zoom_min zoom_max < <(app --benchmark-zoom-range "$ROOT/private-input/$level.level.json" "$ROOT/private-input/collision_table.json" "${query_flags[@]}")
    [[ "$tag" == RUST_ZOOM_RANGE ]]
    digest_every=100
    for ((zoom=zoom_min; zoom<=zoom_max; zoom++)); do
      # RUST_FRAME_DIGEST lines of both variants are compared by the parent.
      # Only idle-600/1200/36000 replays ship in the bundle.
      for variant in normal atlas pipeline; do run_case 600 uncapped; done
    done
    unset digest_every
    printf 'OWNED_ATLAS_CHECK_DONE level=%s benchmark_unverified_level=true\n' "$level"
    ;;
  crowd)
    [[ $# -le 1 ]]; zoom=0
    normalize_level "${1:-mix-2000}"
    for variant in normal single-texture; do run_case 1200 uncapped; done
    printf 'OWNED_STRESS_CROWD_DONE benchmark_unverified_level=true\n'
    ;;
  sustained)
    [[ $# -eq 2 || $# -eq 3 ]]; normalize_level "$1"; zoom=$2; variant=${3:-normal}
    [[ "$zoom" =~ ^-?[0-9]+$ && "$variant" =~ ^(normal|atlas|pipeline)$ ]]
    sensors start | prefix
    run_case 36000 realtime
    sensors end | prefix
    printf 'OWNED_STRESS_SUSTAINED_DONE level=%s zoom=%s calls=36000 benchmark_unverified_level=true\n' "$level" "$zoom"
    ;;
  *) printf 'Unknown stress mode: %s\n' "$mode" >&2; exit 2;;
esac
printf 'OWNED_STRESS_DONE mode=%s benchmark_unverified_level=true\n' "$mode"
