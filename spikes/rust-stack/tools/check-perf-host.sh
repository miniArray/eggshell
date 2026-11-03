#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash nix linuxPackages.perf
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
perf version
cat /proc/sys/kernel/perf_event_paranoid
perf stat -e cpu-clock:u true
