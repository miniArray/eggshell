---
id: 2026-10-30-forgerie-reject-or-honor-scoped-process-clear-protect-child-owned-evidence
title: "Forgerie: reject or honor scoped process.clear; protect child-owned evidence"
status: To Do
created: 2026-10-30
source: forgerie-suggestion
  01a1896f-2ae5-706d-8807-1e4bf5322fa9/7d85d1fb-cc27-449a-b141-d05653237c4d
---

A child in the Eggshell full-Rust experiment called process.clear with id=c1cd36c6-cb19-4117-ac0c-1a83631c6ca7 to remove one ended typo command. The clear branch in /home/simonwjackson/code/sandbox/forgerie/src/server/processes/processTool.ts:123 calls core.clearFinished() before checking args.id, so the supplied ID is silently ignored and all ended records in the session are removed, including parent and sibling-child logs. Actual missing logs were confirmed for eaf3720a-d286-4da1-b85c-24bae957230b and 2954a22a-8e6d-4cc3-be4f-55dc05756ea5.

Follow-up belongs in the Forgerie repository, not Eggshell production code. Make clear semantics explicit and fail closed: honor a supplied ID or reject it rather than silently broadening scope. Decide whether children may clear parent/sibling records at all; add real integration coverage for scoped and unscoped cases, active processes, evidence retention and backing up logs before deletion. Never use a destructive live-session call to test the fix.

Private recovery evidence is outside Git at /home/simonwjackson/.local/share/eggshell-run/full-rust-ab-recovery-20261030-1. It can contain credentials and private art. Do not copy it into an issue, repository, public cache or web service. Parent is recovering tool metadata/output excerpts from private session records and auditing immutable device artifacts; do not claim full stdout recovery until checked.

## Context

### Why
A nominally scoped cleanup silently deleted parent and sibling evidence. This can invalidate audits and erase diagnostic history without the caller understanding the scope.

### Files
- /home/simonwjackson/code/sandbox/forgerie/src/server/processes/processTool.ts
- /home/simonwjackson/code/sandbox/forgerie/skills/processes/SKILL.md

### Decisions
- All agents in this experiment must not call process.clear.
- Recovery copies remain private and separate from live Forgerie state.
- Do not publish incident artifacts or restore stale process metadata over active state.

Suggested in Garden Guardians RG35XX 60fps (01a1896f-2ae5-706d-8807-1e4bf5322fa9), 2026-10-30
