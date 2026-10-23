#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils util-linux
set -euo pipefail
printf '\n=== clock / machine ===\n'
date -Is
uname -a
id korri
printf '\n=== units ===\n'
systemctl is-active korri-compositor korri-chromium-kiosk korrid
printf '\n=== memory ===\n'
free -k
printf '\n=== filesystems ===\n'
findmnt -T /tmp/eggshell
findmnt -T /
df -k /tmp/eggshell /
printf '\n=== graphics / paths ===\n'
ls -l /run/user/1000/wayland-1 /run/opengl-driver/lib /dev/dri/
printf '\n=== native tools ===\n'
for tool in python3 patchelf readelf runuser setpriv tar gzip swaymsg; do command -v "$tool" || true; done
printf '\n=== compositor outputs ===\n'
swaymsg_path=$(find /nix/store -maxdepth 3 -path '*/bin/swaymsg' -print -quit)
if [[ -n "$swaymsg_path" ]]; then
  runuser -u korri -- env SWAYSOCK=/run/korri-compositor/sway-ipc.sock "$swaymsg_path" -t get_outputs || true
fi
printf '\n=== native graphics libraries ===\n'
ls /nix/store/*-wayland-*/lib/libwayland-client.so.0 /nix/store/*-libxkbcommon-*/lib/libxkbcommon.so.0 /nix/store/*-libdecor-*/lib/libdecor-0.so.0 /nix/store/*-libglvnd-*/lib/libEGL.so.1 2>/dev/null || true
printf '\n=== CPU / GPU ===\n'
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq || true
cat /sys/class/devfreq/*/cur_freq 2>/dev/null || true
printf '\n=== Eggshell process audit ===\n'
pgrep -a -f '^/tmp/eggshell/runtime/godot' || true
printf '\n=== native library target ownership (read only) ===\n'
if [[ -d /tmp/eggshell/native-libs ]]; then
  stat -Lc '%U:%G %a %n' /tmp/eggshell/native-libs/*
fi
printf '\n=== existing runtime ===\n'
ls -d /nix/store/*-godot* /nix/store/*-glibc-*/lib/ld-linux-aarch64.so.1 2>/dev/null || true
