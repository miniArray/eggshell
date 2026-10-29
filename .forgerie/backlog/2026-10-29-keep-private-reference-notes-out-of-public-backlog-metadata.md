---
id: 2026-10-29-keep-private-reference-notes-out-of-public-backlog-metadata
title: Keep private reference notes out of public backlog metadata
status: Done
created: 2026-10-29
source: forgerie-suggestion
  01a1896f-2ae5-706d-8807-1e4bf5322fa9/f0dff771-c3ac-4860-b763-eabd681a5063
---

The private publication gate reports 19 forbidden-name/source-reference matches in four tracked `.forgerie/backlog/` cards. Verified on both unchanged baseline `56d75d0` and performance candidate `572ba85`; findings are identical. The four local commits after `28294a2` added these cards and were not pushed by the Pro performance session. No private artwork or level payload was found in the new performance diff.

Resolve backlog storage so public trees contain only neutral summaries and private technical evidence remains in the private repository or local artifact area. Preserve card identity and detailed evidence. Do not weaken the denylist or gate, remove private evidence without a backup, or push the existing local-only research branches.

Reproduce: `python3 /home/simonwjackson/code/sandbox/eggshell-private/publish/gate /home/simonwjackson/code/sandbox/eggshell-release --tree-only --messages-since 56d75d0`.

Acceptance: existing cards remain usable, private details remain recoverable, and the gate returns zero violations on the complete public tracked tree.

## Context

### Why
The existing backlog metadata blocks clean publication even though the new performance code adds no violations. This is separate from the 60 FPS work.

### Files
- .forgerie/backlog/
- /home/simonwjackson/code/sandbox/eggshell-private/publish/gate

### Decisions
- Do not weaken publication checks.
- Preserve the private technical evidence and backlog card identities.
- No public push was made by the Pro performance session.

Suggested in Garden Guardians RG35XX 60fps (01a1896f-2ae5-706d-8807-1e4bf5322fa9), 2026-10-29

## Completion

Commit `cac7092` already removed the reported private references from the four
cards. This follow-up verifies their exact original backups and private ID
mapping, and documents the storage and recovery rules in `docs/backlog.md`.
The four gameplay tasks remain open. Three original IDs are unchanged; the
fourth uses the previously created neutral ID, mapped privately to its original.

Private evidence remains in the local artifact area. All four original backups
match their Git source bytes. Forgerie's scanner reads all 14 cards and keeps
the four gameplay tasks ready. The unchanged complete tracked-tree and
commit-message gate reports zero violations across 406 files. The historical
baseline reproduces all 19 violations. No simulation code,
publication checks, or research branches changed. No branches were pushed.
This check does not sanitize historical trees or authorize their publication.
