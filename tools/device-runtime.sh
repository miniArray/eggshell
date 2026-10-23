#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils util-linux gawk
# Run with bash on the target. All application writes stay under this root.
set -euo pipefail
ROOT=/tmp/eggshell
PID_FILE=$ROOT/eggshell.pid
ENGINE_PID_FILE=$ROOT/eggshell.engine.pid
export PATH=/run/current-system/sw/bin:/usr/bin:/bin

validate_label() {
  [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Invalid log label' >&2; exit 2; }
}

is_ours() {
  [[ -f "$PID_FILE" ]] || return 1
  read -r pid started < "$PID_FILE"
  [[ "$pid" =~ ^[0-9]+$ && -r /proc/$pid/stat ]] || return 1
  [[ "$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null)" == "$started" ]] || return 1
  [[ "$(awk '{print $3}' "/proc/$pid/stat" 2>/dev/null)" != Z ]] || return 1
  local argv=()
  mapfile -d '' -t argv 2>/dev/null < "/proc/$pid/cmdline" || return 1
  [[ "${argv[1]:-}" == "$ROOT/tools/play" ]]
}

engine_is_ours() {
  [[ -f "$ENGINE_PID_FILE" ]] || return 1
  read -r engine_pid engine_started < "$ENGINE_PID_FILE"
  [[ "$engine_pid" =~ ^[0-9]+$ && -r /proc/$engine_pid/stat ]] || return 1
  [[ $(awk '{print $22}' "/proc/$engine_pid/stat" 2>/dev/null) == "$engine_started" ]] || return 1
  [[ $(awk '{print $3}' "/proc/$engine_pid/stat" 2>/dev/null) != Z ]] || return 1
  local command
  IFS= read -r -d '' command 2>/dev/null < "/proc/$engine_pid/cmdline" || return 1
  [[ "$command" == "$ROOT/runtime/godot" ]]
}

native_libraries() {
  mkdir -p "$ROOT/native-libs"
  local sway_pid candidate directory library found
  sway_pid=$(pgrep -u 1000 -x sway | head -n 1)
  mapfile -t directories < <(awk '$NF ~ /^\/nix\/store\/.*\/lib\/[^/]+$/ {path=$NF; sub("/[^/]+$", "", path); print path}' "/proc/$sway_pid/maps" | sort -u)
  for library in libwayland-client.so.0 libwayland-cursor.so.0 libwayland-egl.so.1 libxkbcommon.so.0 libdecor-0.so.0 libEGL.so.1 libGLESv2.so.2 libGL.so.1 libGLX.so.0; do
    found=false
    for directory in "${directories[@]}"; do
      candidate=$directory/$library
      if [[ -f "$candidate" ]]; then
        ln -sf "$candidate" "$ROOT/native-libs/$library"
        found=true
        break
      fi
    done
    if [[ "$found" == false ]]; then
      for candidate in /nix/store/*/lib/"$library"; do
        if [[ -f "$candidate" ]]; then
          ln -sf "$candidate" "$ROOT/native-libs/$library"
          break
        fi
      done
    fi
  done
}

state() {
  date -Is
  for unit in korri-compositor korri-chromium-kiosk korrid; do
    printf '%s=' "$unit"
    systemctl is-active "$unit" || true
  done
  free -k
  findmnt -T "$ROOT"
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq
  cat /sys/class/devfreq/*/cur_freq
}

window_state() {
  local sway_pid swaymsg
  sway_pid=$(pgrep -u 1000 -x sway | head -n 1)
  swaymsg=$(dirname "$(readlink "/proc/$sway_pid/exe")")/swaymsg
  runuser -u korri -- env SWAYSOCK=/run/korri-compositor/sway-ipc.sock "$swaymsg" -t get_outputs
  runuser -u korri -- env SWAYSOCK=/run/korri-compositor/sway-ipc.sock "$swaymsg" -t get_tree
}

start_user() {
  local mode=$1 label=$2 duration=$3 driver=$4
  local engine_args=()
  local args=()
  validate_label "$label"
  [[ "$duration" =~ ^[0-9]+$ ]] || exit 2
  [[ "$driver" == opengl3_es || "$driver" == opengl3 ]] || exit 2
  if is_ours || engine_is_ours; then echo 'Eggshell is already running' >&2; exit 1; fi
  if [[ -e "$ROOT/logs/$label/godot.log" ]]; then echo 'Use a new log label' >&2; exit 2; fi
  mkdir -p "$ROOT/home" "$ROOT/data" "$ROOT/config" "$ROOT/cache" "$ROOT/logs/$label" "$ROOT/write"
  cd "$ROOT"
  case "$mode" in
    bench) ln -sf ../sprites.pck "$ROOT/runtime/godot.pck"; args=("--bench-seconds=$duration") ;;
    game|game-replay)
      ln -sf ../eggshell.pck "$ROOT/runtime/godot.pck"
      args=("--level-code=$ROOT/level.txt" "--save-dir=$ROOT/saves")
      if [[ "$mode" == game-replay ]]; then
        args+=("--save-dir=$ROOT/logs/$label/save" "--replay=res://tests/fixtures/endurance.input.json" "--stop-after=$duration" "--profile")
      fi
      ;;
    write|write-fsync)
      ln -sf ../write-cost.pck "$ROOT/runtime/godot.pck"
      engine_args=(--headless)
      args=("--write-directory=$ROOT/write")
      if [[ "$mode" == write-fsync ]]; then args+=(--write-fsync-tool=/run/current-system/sw/bin/sync); fi
      ;;
    *) echo 'Expected bench, game, game-replay, write, or write-fsync' >&2; exit 2 ;;
  esac
  args+=("${@:5}")
  local cache_home="$ROOT/cache" data_home="$ROOT/data"
  for argument in "${@:5}"; do
    case "$argument" in
      --cold-shader-cache)
        cache_home="$ROOT/logs/$label/cache"
        data_home="$ROOT/logs/$label/data"
        mkdir -p "$cache_home" "$data_home"
        ;;
      --engine-verbose) engine_args+=(--verbose) ;;
    esac
  done
  nohup env HOME="$ROOT/home" XDG_DATA_HOME="$data_home" XDG_CONFIG_HOME="$ROOT/config" XDG_CACHE_HOME="$cache_home" \
    XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 \
    LD_LIBRARY_PATH="$ROOT/runtime/lib:$ROOT/native-libs:/run/opengl-driver/lib" \
    LIBGL_DRIVERS_PATH=/run/opengl-driver/lib/dri \
    __EGL_VENDOR_LIBRARY_FILENAMES=/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json \
    EGGSHELL_ENGINE="$ROOT/runtime/godot" EGGSHELL_ENGINE_PID_FILE="$ENGINE_PID_FILE" \
    EGGSHELL_SHUTDOWN_REQUEST="$ROOT/logs/$label/shutdown" \
    bash "$ROOT/tools/play" --display-driver wayland \
    --rendering-method gl_compatibility --rendering-driver "$driver" --audio-driver Dummy \
    --fullscreen --resolution 640x480 "${engine_args[@]}" \
    -- "--frame-log=$ROOT/logs/$label/frames.csv" "${args[@]}" \
    > "$ROOT/logs/$label/godot.log" 2>&1 < /dev/null &
  pid=$!
  started=$(awk '{print $22}' "/proc/$pid/stat")
  printf '%s %s\n' "$pid" "$started" > "$PID_FILE"
  echo "Started Eggshell PID $pid; logs: $ROOT/logs/$label"
}

stop() {
  if is_ours; then kill -TERM "$pid"; fi
  for _ in {1..50}; do
    if ! is_ours && ! engine_is_ours; then break; fi
    sleep 0.1
  done
  if engine_is_ours; then
    echo 'Graceful shutdown timed out; killing owned engine' >&2
    kill -KILL "$engine_pid"
  fi
  if is_ours; then kill -KILL "$pid"; fi
  rm -f "$PID_FILE" "$ENGINE_PID_FILE"
}

case "${1:-}" in
  setup)
    native_libraries
    ln -sf ../eggshell.pck "$ROOT/runtime/godot.pck"
    mkdir -p "$ROOT/logs" "$ROOT/home" "$ROOT/data" "$ROOT/config" "$ROOT/cache" "$ROOT/write"
    # User progress in saves-user-* is not ours. Never recurse over ROOT.
    chown korri:korri "$ROOT"
    chown -hR korri:korri "$ROOT/runtime" "$ROOT/tools" "$ROOT/native-libs" "$ROOT/logs" "$ROOT/home" "$ROOT/data" "$ROOT/config" "$ROOT/cache" "$ROOT/write"
    chmod +x "$ROOT/runtime/godot"
    ;;
  start)
    shift
    runuser -u korri -- bash "$0" start-user "$@"
    ;;
  start-user)
    shift
    start_user "$@"
    ;;
  stop) stop ;;
  status)
    if is_ours; then echo "running wrapper $pid"; elif engine_is_ours; then echo "running owned engine $engine_pid"; else echo stopped; exit 3; fi
    ;;
  state) state ;;
  measure)
    mode=$2 label=$3 duration=${4:-60} kiosk=${5:-keep} driver=${6:-opengl3_es}
    validate_label "$label"
    [[ "$duration" =~ ^[0-9]+$ && ( "$kiosk" == keep || "$kiosk" == pause ) ]] || exit 2
    if is_ours || engine_is_ours; then echo 'Eggshell is already running' >&2; exit 1; fi
    if [[ -e "$ROOT/logs/$label" ]]; then echo 'Use a new log label' >&2; exit 2; fi
    mkdir -p "$ROOT/logs/$label"
    chown korri:korri "$ROOT/logs/$label"
    state > "$ROOT/logs/$label/before.txt"
    restore=false
    cleanup() {
      stop
      if [[ "$restore" == true ]]; then systemctl start korri-chromium-kiosk; fi
      state > "$ROOT/logs/$label/after.txt"
    }
    trap cleanup EXIT
    trap 'exit 130' INT TERM HUP
    if [[ "$kiosk" == pause ]] && systemctl is-active --quiet korri-chromium-kiosk; then
      restore=true
      systemctl stop korri-chromium-kiosk
    fi
    state > "$ROOT/logs/$label/during.txt"
    bash "$0" start "$mode" "$label" "$duration" "$driver" "${@:7}"
    deadline=$((SECONDS + duration + 60))
    sleep 1
    window_state > "$ROOT/logs/$label/window.txt"
    state > "$ROOT/logs/$label/running.txt"
    snapshot_at=$((SECONDS + 14))
    snapshot_taken=false
    while is_ours || engine_is_ours; do
      if [[ "$snapshot_taken" == false ]] && (( SECONDS >= snapshot_at )); then
        window_state > "$ROOT/logs/$label/window.txt"
        state > "$ROOT/logs/$label/running.txt"
        snapshot_taken=true
      fi
      if (( SECONDS > deadline )); then
        cat "$ROOT/logs/$label/godot.log"
        echo 'Measurement timed out' >&2
        exit 1
      fi
      sleep 1
    done
    cat "$ROOT/logs/$label/godot.log"
    if [[ "$mode" == bench || "$mode" == game-replay ]]; then
      test -s "$ROOT/logs/$label/frames.csv.summary.json"
    elif [[ "$mode" == write ]]; then
      grep -q '^EGGSHELL_WRITE_SUMMARY ' "$ROOT/logs/$label/godot.log"
      test -s "$ROOT/write/gdscript-write.summary.json"
    elif [[ "$mode" == write-fsync ]]; then
      grep -q '^EGGSHELL_WRITE_SUMMARY ' "$ROOT/logs/$label/godot.log"
      test -s "$ROOT/write/gdscript-fsync.summary.json"
    fi
    ;;
  *) echo 'Expected setup, start, stop, status, state, or measure' >&2; exit 2 ;;
esac
