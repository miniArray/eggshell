---
id: 2026-10-28-device-measurements-control-for-korrid-cpu-load-during-frame-rate-runs
title: "Device measurements: control for korrid CPU load during frame-rate runs"
status: To Do
created: 2026-10-28
source: forgerie-suggestion
  01a18311-a554-739b-9012-067bcd50199d/3fb3403e-0c21-475c-9a8d-30f58bd3ac69
---

On the RG35XX Pro, `korrid` sometimes uses 100-190% of one core. A run of fixed main 0eabc35 (Endurance replay, Pantry, `measure game-replay <label> 120 pause opengl3_es`) fell to 53.9 fps with p99 44.9 ms while korrid used 103%. The two runs before and after it gave 59.9 fps with p99 about 20.7 ms. Every slow frame in the bad run fell between 40 s and 80 s.

`measure` pauses only `korri-chromium-kiosk`. It does not record or limit korrid. As a result, one frame-rate number can look like a regression when the cause is device load.

Steps:
1. Record korrid CPU before and after each run inside `tools/device-runtime.sh measure`. `/tmp/fps-bisect/korrid-cpu.sh` and `measure.sh` show the method: compare /proc/<pid>/stat utime+stime against uptime.
2. Find out why korrid gets busy. Then decide whether `pause` should also stop it, or whether a run should be flagged and repeated when korrid load is above a threshold.

## Context

### Why
The original 52-54 fps reports most likely came from this load. It will keep confusing later art and performance checks on the device.

### Files
- tools/device-runtime.sh
- tools/device.py

### Decisions
- The engine regression (autosave schema rebuild) is fixed separately in 38357ec. This card covers only measurement noise.

Suggested in This is backlog item (01a18311-a554-739b-9012-067bcd50199d), 2026-10-28
