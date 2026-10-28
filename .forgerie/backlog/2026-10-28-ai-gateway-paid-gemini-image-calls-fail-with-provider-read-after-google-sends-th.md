---
id: 2026-10-28-ai-gateway-paid-gemini-image-calls-fail-with-provider-read-after-google-sends-th
title: "ai-gateway: paid Gemini image calls fail with provider_read after Google
  sends the image (money lost)"
status: To Do
created: 2026-10-28
source: forgerie-suggestion
  01a1844a-0c7e-768c-88ad-2f6016b1477a/7baec337-08de-41cb-b320-7c1aafc6902f
---

On 2026-10-28, `gemini-3-pro-image` calls through the front door on rakku failed with `502 provider_read` ("provider response failed"):
- From 20:15 to 20:34 UTC, about half of the 1K single-frame calls failed. The failures came in a strict 200/502 alternation.
- From 21:11 to 21:17 UTC, 8 of 8 calls at 2K and 3K failed.

The squid egress access log (`/run/ai-gateway-egress/access.log`) shows that each failed call's tunnel carried about 3.5 MB, which is as much as a successful call carried. So Google most likely returned the image and billed it, and the gateway then failed while reading the body (`read_limited` in `crates/front-door/src/lib.rs:736`, used by `images.rs:426` through `paid_json_client`, which has gzip, brotli, deflate and zstd decoding on and HTTP/2). At 21:21 a direct curl through the same proxy returned 402 "prepayment credits are depleted". The lost calls probably helped use up the credits.

Suspects:
- Response decompression, because the paid JSON client decodes gzip and Google sends `content-encoding: gzip`.
- HTTP/2 stream handling through the CONNECT tunnel.
- A body read timeout.

The gateway logs only the 502, not the reqwest error. The first step is to log `cause` on the chunk error in `read_limited`. Then reproduce with one call once the credits are refilled.

Steps:
1. Log the reqwest error.
2. Reproduce.
3. Fix it, for example by turning off decoding and decompressing manually, or by forcing HTTP/1.1 for the paid image call.
4. Add a test with a large gzip body.
5. Deploy to rakku with the guarded scripts.

## Context

### Why
Every failed call likely costs about $0.24 at Google but returns no image. This blocks Verdigris animation frames and the pack 4 background layers.

### Files
- ~/code/sandbox/ai-gateway/crates/front-door/src/lib.rs
- ~/code/sandbox/ai-gateway/crates/front-door/src/images.rs

### Decisions
- The 21:11-21:17 failures were 200 responses that broke during the body read, not 402s: a 402 would pass through as 402 (`stream_response`)

Suggested in herion (01a1844a-0c7e-768c-88ad-2f6016b1477a), 2026-10-28
