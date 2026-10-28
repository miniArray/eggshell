---
id: 2026-10-28-ai-gateway-pass-image-size-to-gemini-imageconfig-so-one-call-can-hold-a-whole-an
title: "ai-gateway: pass image size to Gemini (imageConfig) so one call can hold
  a whole animation cycle"
status: To Do
created: 2026-10-28
source: forgerie-suggestion
  01a18311-c7b8-739b-9012-06800297a554/ccfb7d3b-9df5-45fe-865c-86fb461c617f
---

The front door accepts `size` on `/v1/images/*` but drops it for Gemini models (`crates/front-door/src/images.rs`: `GeminiGenerationConfig` only sets `responseModalities`). Nano Banana Pro then returns about 1 MP, which fits one Verdigris sprite of Oriel at about 10 raw px per art px.

If the front door mapped `size` to Gemini's `imageConfig` (`imageSize` 2K/4K and `aspectRatio`), one 4K call could hold a 6-frame cycle at the art brief's grid. Frames drawn in one image stay more consistent with each other, and one 4K call (about $0.24) costs less than six 1K calls (about $0.80).

Work: map size to imageConfig, price 4K correctly against the paid cap, test, deploy to rakku with the guarded scripts. Then adapt `art-direction/oriel/anim-1/work/gen.py` to a sheet layout if it is worth it.

## Context

### Why
Found while preparing the Oriel animation frames: the gateway limits Nano Banana Pro to about 1 MP, so each frame is a separate call.

### Files
- ~/code/sandbox/ai-gateway/crates/front-door/src/images.rs
- ~/.local/share/eggshell/art-direction/oriel/anim-1/work/gen.py

### Decisions
- anim-1 uses one 1K call per frame because the gateway ignores size for Gemini

Suggested in Verdigris animation frames backlog (01a18311-c7b8-739b-9012-06800297a554), 2026-10-28
