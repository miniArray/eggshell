#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils linuxPackages.perf
# aka only. Usage: perf-callers.sh PERF_DATA SYMBOL_SUBSTRING...  Caller chains for matching self-time symbols.
set -uo pipefail
[[ $(hostname) == aka ]]
data=$1
shift
for symbol in "$@"; do
  printf 'CALLERS %s\n' "$symbol"
  perf report -i "$data" --stdio --no-children --sort symbol -g caller,2,callee,function,percent \
    --symbol-filter="$symbol" 2>/dev/null | grep -v '^$' | grep -v '^#' | cut -c1-180 | head -60
done
printf 'CALLERS_DONE\n'
