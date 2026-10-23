#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils util-linux gawk
set -euo pipefail
ROOT=/tmp/eggshell
export PATH=/run/current-system/sw/bin:/usr/bin:/bin
if (( EUID == 0 )); then
  exec runuser -u korri -- bash "$0"
fi
cd "$ROOT"
mkdir -p "$ROOT/write"
findmnt -T "$ROOT" > "$ROOT/write/filesystem.txt"
dd if=/dev/zero of="$ROOT/write/payload.bin" bs=4096 count=1 status=none
samples=()
for ((index=0; index<210; index++)); do
  start=${EPOCHREALTIME/./}
  dd if="$ROOT/write/payload.bin" of="$ROOT/write/shell-save.new" bs=4096 count=1 conv=fsync status=none
  mv -T "$ROOT/write/shell-save.new" "$ROOT/write/shell-save.bin"
  end=${EPOCHREALTIME/./}
  if (( index >= 10 )); then samples+=("$((end - start))"); fi
done
{
  echo operation_us
  printf '%s\n' "${samples[@]}"
} > "$ROOT/write/shell-write.csv"
mapfile -t sorted < <(printf '%s\n' "${samples[@]}" | sort -n)
printf '{"operation":"dd open + write + fsync + close + mv rename, including two process launches; NO directory fsync","bytes":4096,"iterations":200,"warmup_iterations":10,"p50_us":%s,"p99_us":%s}\n' \
  "${sorted[99]}" "${sorted[197]}" | tee "$ROOT/write/shell-write.summary.json"
