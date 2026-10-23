#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix util-linux
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
label=${1:-host}
duration=${2:-60}
[[ "$label" =~ ^[a-zA-Z0-9_-]+$ && "$duration" =~ ^[0-9]+$ ]] || exit 2
mkdir -p "$ROOT/build/logs/$label"
nix build "$ROOT#godot" --out-link "$ROOT/build/godot"
{
  date -Is
  uname -a
  lscpu
  free -k
} > "$ROOT/build/logs/$label/before.txt"
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/1000}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
export HOME="$ROOT/build/host-home" XDG_DATA_HOME="$ROOT/build/host-data" XDG_CACHE_HOME="$ROOT/build/host-cache" XDG_CONFIG_HOME="$ROOT/build/host-config"
mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
"$ROOT/build/godot/bin/godot" --path "$ROOT" --display-driver wayland \
  --rendering-method gl_compatibility --rendering-driver opengl3_es --audio-driver Dummy \
  --windowed --resolution 640x480 res://bench/sprites.tscn \
  -- "--bench-seconds=$duration" "--frame-log=$ROOT/build/logs/$label/frames.csv" \
  > "$ROOT/build/logs/$label/godot.log" 2>&1 &
godot_pid=$!
trap 'kill -TERM "$godot_pid" 2>/dev/null || true' EXIT
# The host uses a tiling, headless Sway. Change only this process's window.
sleep 1
sway_pid=$(pgrep -u "$(id -u)" -x sway | head -n 1 || true)
if [[ -n "$sway_pid" && -S /run/korri-compositor/sway-ipc.sock ]]; then
  swaymsg=$(dirname "$(readlink "/proc/$sway_pid/exe")")/swaymsg
  for _ in {1..40}; do
    if SWAYSOCK=/run/korri-compositor/sway-ipc.sock "$swaymsg" "[pid=$godot_pid] floating enable, resize set width 640 px height 480 px" \
      > "$ROOT/build/logs/$label/window.txt"; then
      break
    fi
    sleep 0.25
  done
fi
wait "$godot_pid"
trap - EXIT
cat "$ROOT/build/logs/$label/godot.log"
{
  date -Is
  free -k
} > "$ROOT/build/logs/$label/after.txt"
test -s "$ROOT/build/logs/$label/frames.csv.summary.json"
