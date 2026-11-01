#!/run/current-system/sw/bin/bash
# Level list entry: pick a level from the list, play it, come back to the list.
# List: D-pad move (hold to repeat), L1/R1 page, A or Start play, B back, Select+Start quit.
# In a level: the playtest controls (launch-playtest); Select+Start returns to the list.
# Each level continues from its own autosave. Usage: launch-levels SECONDS [shots]
# shots: unattended pictures of the list (scripted commands) and of the levels named in
# private-input/level-shots.txt (idle steps), into data/shots-levels.
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
seconds=${1:-900}
[[ "$seconds" =~ ^[1-9][0-9]{0,2}$ && "$seconds" -le 900 ]]
LEVELS="$ROOT/private-input/levels"
INDEX="$ROOT/private-input/level-index.json"
TARGET_FILE=6600ab52a3bb0805d316b9f1.json
[[ -f "$INDEX" && -d "$LEVELS" ]]
mkdir -p "$ROOT/data"
player() {
  "$ROOT/lib/ld-linux-aarch64.so.1" --library-path "$LIBPATH" "$ROOT/bin/eggshell-spike-player" "$@"
}
pack=(--pack-root "$ROOT/private-pack" --pack-inventory "$ROOT/private-pack/pack-files.sha256.json"
  --view-metrics "$ROOT/private-input/view-metrics.json")
play() {
  local file=$1 save=$2 left=$3
  shift 3
  local bound=$((left + 15))
  ((bound <= 900)) || bound=900
  player --play --level "$LEVELS/$file" --collision "$ROOT/private-input/collision_table.json" \
    --schema "$ROOT/private-input/schema.json" "${pack[@]}" \
    --ticks $((left * 60)) --seconds "$bound" --save-dir "$save" "$@"
}
# The target keeps the save folder of launch-playtest, so autosaves carry across both.
save_dir() {
  if [[ $1 == "$TARGET_FILE" ]]; then
    printf '%s\n' "$ROOT/data/playtest-target"
  else
    printf '%s\n' "$ROOT/data/playtest-${1%.*}"
  fi
}
if [[ "${2:-}" == shots ]]; then
  shots="$ROOT/data/shots-levels"
  mkdir -p "$shots/list"
  choice=$(mktemp "$ROOT/data/choice-XXXXXX")
  printf 'LEVELS_SHOTS_BEGIN\n'
  player --levels --index "$INDEX" --choice "$choice" "${pack[@]}" --seconds 60 \
    --script down,down,down,page_down,page_down,page_up,back,confirm,confirm --frame-dump-dir "$shots/list" || true
  rm -f "$choice"
  if [[ -f "$ROOT/private-input/level-shots.txt" ]]; then
    # Lines: FILE X Y LABEL; X Y "-" keep the game camera, else the view centres there.
    while read -r file x y label; do
      [[ "$file" =~ ^[A-Za-z0-9_.-]+$ && -f "$LEVELS/$file" && "$label" =~ ^[a-z0-9]+$ ]] || continue
      view=()
      if [[ "$x" != - ]]; then
        [[ "$x" =~ ^-?[0-9.]+$ && "$y" =~ ^-?[0-9.]+$ ]] || continue
        view=(--view-at "$x,$y")
      fi
      out="$shots/${file%.*}-$label"
      mkdir -p "$out"
      save=$(mktemp -d "$ROOT/data/shots-run-XXXXXX")
      printf 'LEVELS_SHOTS_LEVEL %s %s\n' "$file" "$label"
      play "$file" "$save" 5 --replay "$ROOT/private-input/idle-600.input.json" --ticks 300 \
        --frame-digest-every 100 --frame-dump-dir "$out" --no-pipeline "${view[@]}" ||
        printf 'LEVELS_SHOTS_FAILED %s %s\n' "$file" "$label"
    done < "$ROOT/private-input/level-shots.txt"
  fi
  printf 'LEVELS_SHOTS_DONE dir=%s\n' "$shots"
  exit 0
fi
# Wall-clock seconds from date, not bash's SECONDS: on the Pro, a launch-levels started
# from owned-playtest.sh saw SECONDS near 2e14 (deadline already past), so every
# hands-on session since 949aa5a ended at once.
now() { date +%s; }
deadline=$(($(now) + seconds))
focus=()
status=()
printf 'LEVELS_BEGIN seconds=%s\n' "$seconds"
while left=$((deadline - $(now))); ((left > 2)); do
  choice=$(mktemp "$ROOT/data/choice-XXXXXX")
  player --levels --index "$INDEX" --choice "$choice" "${pack[@]}" --seconds "$left" "${focus[@]}" "${status[@]}"
  file=$(cat "$choice")
  rm -f "$choice"
  [[ -n "$file" ]] || break
  focus=(--focus "$file")
  status=()
  if ! [[ "$file" =~ ^[A-Za-z0-9_.-]+$ && -f "$LEVELS/$file" ]]; then
    status=(--status "Cannot open $file: the level file is missing")
    continue
  fi
  left=$((deadline - $(now)))
  ((left > 1)) || break
  save=$(save_dir "$file")
  mkdir -p "$save"
  printf 'LEVELS_PLAY file=%s seconds=%s\n' "$file" "$left"
  if [[ -f "$save/autosave.v10" ]]; then
    cp "$save/autosave.v10" "$save/continue.v10"
    if ! play "$file" "$save" "$left" --presentation-feedback --restore "$save/continue.v10"; then
      mv "$save/continue.v10" "$save/autosave.v10.refused"
      printf 'LEVELS_CONTINUE_REFUSED file=%s starting_fresh=true\n' "$file"
      left=$((deadline - $(now)))
      ((left > 1)) || break
      play "$file" "$save" "$left" --presentation-feedback ||
        status=(--status "Cannot play $file: the game stopped with an error")
    fi
  elif ! play "$file" "$save" "$left" --presentation-feedback; then
    status=(--status "Cannot play $file: the game stopped with an error")
  fi
done
printf 'LEVELS_DONE\n'
