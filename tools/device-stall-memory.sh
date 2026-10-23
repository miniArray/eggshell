#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils gawk
set -euo pipefail
ROOT=/tmp/eggshell
read -r pid started < "$ROOT/eggshell.engine.pid"
[[ $(awk '{print $22}' "/proc/$pid/stat") == "$started" ]]
label=${1:?label}
[[ "$label" =~ ^[a-zA-Z0-9_-]+$ ]]
tr '\0' '\n' < "/proc/$pid/cmdline" | grep -Fq -- "--frame-log=$ROOT/logs/$label/frames.csv"
cat "/proc/$pid/smaps" > "$ROOT/logs/$label/smaps.txt"
cat "/proc/$pid/status"
