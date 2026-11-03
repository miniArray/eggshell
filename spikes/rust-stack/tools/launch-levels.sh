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
export SDL_VIDEODRIVER=wayland SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=0
# Sound as in launch-playtest: SDL tries the PulseAudio protocol (the Pro's sound
# server), then ALSA; without either the game runs silent and says so.
unset SDL_AUDIODRIVER
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
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
    --ticks $((left * 60)) --seconds "$bound" --save-dir "$save" "${tiles[@]}" "$@"
}
# The original's animated tileset frames, when the bundle has them.
tiles=()
if [[ -d "$ROOT/private-animated-tiles" ]]; then tiles=(--animated-tiles "$ROOT/private-animated-tiles"); fi
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
  # Spit check on the public stride fixture: walk right 110 steps, lick (catch a Shy Guy),
  # wait 20 steps, spit, then 80 idle steps; a picture every 3 steps.
  spit_route="$ROOT/data/spit-route.json"
  {
    printf '['
    for ((i = 0; i < 211; i++)); do
      if ((i > 0)); then printf ','; fi
      if ((i < 110)); then printf 2; elif ((i == 110 || i == 131)); then printf 8; else printf 0; fi
    done
    printf ']\n'
  } > "$spit_route"
  mkdir -p "$shots/stride-spit"
  save=$(mktemp -d "$ROOT/data/shots-run-XXXXXX")
  printf 'LEVELS_SHOTS_SPIT\n'
  player --play --level "$ROOT/private-input/stride.level.json" --collision "$ROOT/private-input/collision_table.json" \
    --schema "$ROOT/private-input/schema.json" "${pack[@]}" --save-dir "$save" "${tiles[@]}" --replay "$spit_route" \
    --ticks 170 --seconds 30 --frame-digest-every 3 --frame-dump-dir "$shots/stride-spit" --no-pipeline ||
    printf 'LEVELS_SHOTS_FAILED stride spit\n'
  # The hands-on check level (PLAYER_EXTRA_LEVELS 0-check.json), one host-checked route:
  # walk and lick the Shy Guys (USE), lay each egg (DOWN), stand 2 s with 4 eggs (calls
  # 540-660), hop past the shell Koopa (its runner), stop at x ~1960 facing the Snifit
  # and stand while it shoots (pellets visible from call ~900).
  if [[ -f "$LEVELS/0-check.json" ]]; then
    route="$ROOT/data/check-route.json"
    {
      printf '['
      n=0
      emit() { if ((n > 0)); then printf ','; fi; printf '%s' "$1"; n=$((n + 1)); }
      for ((k = 0; k < 9; k++)); do
        for ((i = 0; i < 30; i++)); do emit 2; done
        emit 8
        for ((i = 0; i < 15; i++)); do emit 0; done
        emit 32
        for ((i = 0; i < 13; i++)); do emit 0; done
      done
      for ((i = 0; i < 120; i++)); do emit 0; done
      for ((i = 0; i < 160; i++)); do if (((i + 20) % 60 >= 46)); then emit 6; else emit 2; fi; done
      for ((i = 0; i < 300; i++)); do emit 0; done
      printf ']\n'
    } > "$route"
    mkdir -p "$shots/0-check"
    save=$(mktemp -d "$ROOT/data/shots-run-XXXXXX")
    printf 'LEVELS_SHOTS_CHECK route\n'
    play 0-check.json "$save" 25 --replay "$route" --ticks 1120 \
      --frame-digest-every 10 --frame-dump-dir "$shots/0-check" --no-pipeline ||
      printf 'LEVELS_SHOTS_FAILED 0-check\n'
  fi
  # Animated tilesets: Toxic Tunnel (flowing water) idle, a picture every 3 steps.
  toxic=6a01fef0729b503561e9de41.json
  if [[ -f "$LEVELS/$toxic" ]]; then
    mkdir -p "$shots/${toxic%.*}-water"
    save=$(mktemp -d "$ROOT/data/shots-run-XXXXXX")
    printf 'LEVELS_SHOTS_WATER %s\n' "$toxic"
    play "$toxic" "$save" 5 --replay "$ROOT/private-input/idle-600.input.json" --ticks 30 \
      --frame-digest-every 3 --frame-dump-dir "$shots/${toxic%.*}-water" --no-pipeline ||
      printf 'LEVELS_SHOTS_FAILED %s water\n' "$toxic"
  fi
  # Goal menu pictures: the newest earlier autosaves of listed levels (a completed
  # level opens the goal menu at once; others just play 60 steps without input).
  n=0
  while IFS= read -r saved && ((n < 4)); do
    dir=$(basename "$(dirname "$saved")")
    file="${dir#playtest-}.json"
    [[ "$file" =~ ^[A-Za-z0-9_.-]+$ && -f "$LEVELS/$file" ]] || continue
    n=$((n + 1))
    out="$shots/${file%.*}-goal"
    mkdir -p "$out"
    save=$(mktemp -d "$ROOT/data/shots-run-XXXXXX")
    cp "$saved" "$save/from-autosave.v10"
    printf 'LEVELS_SHOTS_GOAL %s from=%s\n' "$file" "$saved"
    play "$file" "$save" 2 --restore "$save/from-autosave.v10" --ticks 60 --result "$save/goal-result" \
      --frame-dump-dir "$out" --no-pipeline || printf 'LEVELS_SHOTS_FAILED %s goal\n' "$file"
    printf 'LEVELS_SHOTS_GOAL_RESULT %s %s\n' "$file" "$(cat "$save/goal-result" 2>/dev/null || echo none)"
  done < <(find /tmp -maxdepth 4 -path '/tmp/eggshell-full-rust-owned-*/data/playtest-*/autosave.v10' -printf '%T@ %p\n' 2>/dev/null |
    sort -rn | cut -d' ' -f2-)
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
next=
printf 'LEVELS_BEGIN seconds=%s\n' "$seconds"
while left=$((deadline - $(now))); ((left > 2)); do
  if [[ -n "$next" ]]; then
    file=$next
    next=
  else
    choice=$(mktemp "$ROOT/data/choice-XXXXXX")
    player --levels --index "$INDEX" --choice "$choice" "${pack[@]}" --seconds "$left" "${focus[@]}" "${status[@]}"
    file=$(cat "$choice")
    rm -f "$choice"
  fi
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
  # The goal menu (game.gd) writes next, restart, levels or quit here.
  result="$save/goal-result"
  rm -f "$result"
  after=$(player --next-level "$INDEX" "$file")
  goal=(--result "$result")
  if [[ -n "$after" ]]; then goal+=(--has-next); fi
  printf 'LEVELS_PLAY file=%s seconds=%s\n' "$file" "$left"
  if [[ -f "$save/autosave.v10" ]]; then
    cp "$save/autosave.v10" "$save/continue.v10"
    if ! play "$file" "$save" "$left" --presentation-feedback "${goal[@]}" --restore "$save/continue.v10"; then
      mv "$save/continue.v10" "$save/autosave.v10.refused"
      printf 'LEVELS_CONTINUE_REFUSED file=%s starting_fresh=true\n' "$file"
      left=$((deadline - $(now)))
      ((left > 1)) || break
      play "$file" "$save" "$left" --presentation-feedback "${goal[@]}" ||
        status=(--status "Cannot play $file: the game stopped with an error")
    fi
  elif ! play "$file" "$save" "$left" --presentation-feedback "${goal[@]}"; then
    status=(--status "Cannot play $file: the game stopped with an error")
  fi
  outcome=$(cat "$result" 2>/dev/null || true)
  printf 'LEVELS_GOAL file=%s choice=%s\n' "$file" "${outcome:-none}"
  case "$outcome" in
    next) next=$after ;;
    restart)
      # A fresh start: the completed autosave would reopen the goal menu.
      rm -f "$save/autosave.v10"
      next=$file
      ;;
    quit) break ;;
  esac
done
printf 'LEVELS_DONE\n'
