#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils
# Wake the display for a real visible run. This does not change compositor config.
set -euo pipefail
export PATH=/run/current-system/sw/bin:/usr/bin:/bin
ROOT=/tmp/eggshell
pid=$(pgrep -u 1000 -x sway | head -n 1)
swaymsg=$(dirname "$(readlink "/proc/$pid/exe")")/swaymsg
runuser -u korri -- env SWAYSOCK=/run/korri-compositor/sway-ipc.sock "$swaymsg" -t get_outputs > "$ROOT/logs/display-before.json"
runuser -u korri -- env SWAYSOCK=/run/korri-compositor/sway-ipc.sock "$swaymsg" output DSI-1 power on
sleep 1
runuser -u korri -- env SWAYSOCK=/run/korri-compositor/sway-ipc.sock "$swaymsg" -t get_outputs > "$ROOT/logs/display-after.json"
