#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils procps
# Diagnose and terminate only an engine whose exact run label proves ownership.
set -euo pipefail
export PATH=/run/current-system/sw/bin:/usr/bin:/bin
ROOT=/tmp/eggshell
label=$1
[[ "$label" =~ ^[a-zA-Z0-9_-]+$ ]] || exit 2
log=$ROOT/logs/$label/godot.log
engine=$(awk '$1=="EGGSHELL_ENGINE_PID" {print $2; exit}' "$log")
[[ "$engine" =~ ^[0-9]+$ && -r /proc/$engine/cmdline ]] || exit 0
tr '\0' '\n' < "/proc/$engine/cmdline" | grep -Fx -- "--frame-log=$ROOT/logs/$label/frames.csv"
{
  date -Is
  ps -L -p "$engine" -o pid,tid,comm,wchan:40
  for task in /proc/"$engine"/task/*; do
    printf '%s ' "${task##*/}"
    cat "$task/comm" "$task/wchan"
    printf '\n'
  done
  ls -l "$ROOT/logs/$label"
} > "$ROOT/logs/$label/hang.txt"
kill -TERM "$engine"
for _ in {1..50}; do
  [[ -e /proc/$engine ]] || break
  sleep 0.1
done
if [[ -e /proc/$engine ]] && [[ $(awk '{print $3}' "/proc/$engine/stat") != Z ]]; then
  tr '\0' '\n' < "/proc/$engine/cmdline" | grep -Fx -- "--frame-log=$ROOT/logs/$label/frames.csv"
  kill -KILL "$engine"
fi
echo "Recovered owned engine $engine ($label); this run is NOT a passing measurement"
