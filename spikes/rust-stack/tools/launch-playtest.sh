#!/run/current-system/sw/bin/bash
# Playtest entry: plays one unchanged level in real time with the device controls.
# Controls: D-pad move, A/B jump, X/Y tongue, L throw/aim, R aim lock, Down pound/lay,
# Select+L/R zoom, Select+Start quits. Ends after the given seconds of steps (wall limit 15 s more).
# Continue: the autosave of the last session is restored. A save the build refuses
# is kept as autosave.v10.refused and the level starts fresh.
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
level=${1:-target}
seconds=${2:-900}
[[ "$seconds" =~ ^[1-9][0-9]{0,2}$ && "$seconds" -le 900 ]]
[[ "$level" =~ ^[a-z0-9_.-]+$ && -f "$ROOT/private-input/$level.level.json" ]]
save="$ROOT/data/playtest-$level"
mkdir -p "$save"
play() {
  "$ROOT/lib/ld-linux-aarch64.so.1" --library-path "$LIBPATH" "$ROOT/bin/eggshell-spike-player" --play \
    --level "$ROOT/private-input/$level.level.json" --collision "$ROOT/private-input/collision_table.json" \
    --schema "$ROOT/private-input/schema.json" --pack-root "$ROOT/private-pack" \
    --pack-inventory "$ROOT/private-pack/pack-files.sha256.json" --view-metrics "$ROOT/private-input/view-metrics.json" \
    --ticks $((seconds * 60)) --seconds $((seconds + 15)) --save-dir "$save" --presentation-feedback "$@"
}
if [[ "${3:-}" == replay ]]; then
  # Unattended check: plays the recorded route inputs, from a fresh start, saves aside.
  save=$(mktemp -d "$ROOT/data/replay-$level-XXXXXX")
  printf 'PLAYTEST_BEGIN level=%s replay=true seconds=%s\n' "$level" "$seconds"
  play --replay "$ROOT/private-input/$level.input.json"
elif [[ -f "$save/autosave.v10" ]]; then
  cp "$save/autosave.v10" "$save/continue.v10"
  printf 'PLAYTEST_BEGIN level=%s continue=true seconds=%s\n' "$level" "$seconds"
  if ! play --restore "$save/continue.v10"; then
    mv "$save/continue.v10" "$save/autosave.v10.refused"
    printf 'PLAYTEST_CONTINUE_REFUSED level=%s starting_fresh=true\n' "$level"
    play
  fi
else
  printf 'PLAYTEST_BEGIN level=%s continue=false seconds=%s\n' "$level" "$seconds"
  play
fi
printf 'PLAYTEST_DONE level=%s\n' "$level"
