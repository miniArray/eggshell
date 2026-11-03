#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils
# Persist complete command/output independently of shared managed-process records.
set -euo pipefail
[[ $(hostname) == aka ]]
export NIX_CONFIG='builders ='
umask 077
label=${1:?private log label required}
shift
[[ "$label" =~ ^[A-Za-z0-9_-]+$ && "$#" -gt 0 ]]
OUT="$HOME/eggshell-remote/artifacts/full-rust-ab/player/durable-logs"
mkdir -p "$OUT"
LOG="$OUT/$label-$(date -u +%Y%m%dT%H%M%S)-$$.log"
(set -o noclobber; : > "$LOG")
{
  printf 'PRIVATE_COMMAND'
  printf ' %q' "$@"
  printf '\nPRIVATE_SOURCE %s\n' "$(git rev-parse HEAD)"
} | tee -a "$LOG"
set +e
"$@" 2>&1 | tee -a "$LOG"
status=${PIPESTATUS[0]}
set -e
printf 'PRIVATE_COMMAND_EXIT %s\nDURABLE_LOG %s\n' "$status" "$LOG" | tee -a "$LOG"
exit "$status"
