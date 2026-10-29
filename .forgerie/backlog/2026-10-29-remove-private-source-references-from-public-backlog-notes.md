---
id: 2026-10-29-remove-private-source-references-from-public-backlog-notes
title: Remove private-source references from public backlog notes
status: Done
created: 2026-10-29
source: forgerie-suggestion
  01a188f3-34da-70e1-a56d-7d6155bc7ec4/86c0b7f7-b2ed-4757-8035-ac0a5b9fe92c
---

The staged public-tree publication gate scans 404 files and reports four forbidden-text findings in three existing `.forgerie/backlog` notes. A detached checkout of base commit `5680d23770ba5a1dd37f9b721762bd39e175b80c` reports the same four findings across its 401 files. The plant changes add no findings.

Keep the backlog tasks, but move source-only provenance to private reports and rewrite the public notes without private source identifiers. Do not remove the tasks or change simulation behavior. Rerun the private publication gate on the complete tracked tree before publication.

The exact report is private: `~/.local/share/eggshell-run/plant-fix/public-tree-gate.json`.

## Context

### Why
High: the current public tree fails its publication gate, independently of the plant fix.

### Files
- .forgerie/backlog/2026-10-29-eggshell-fix-the-remaining-missed-and-extra-enemy-contacts-found-by-review.md
- .forgerie/backlog/2026-10-29-eggshell-plant-capture-and-release-path-head-width-and-aim-order.md
- .forgerie/backlog/2026-10-29-eggshell-process-player-input-events-during-the-companion-catch-freeze.md

### Decisions
- All four findings also occur in the unchanged base commit.
- Preserve the backlog tasks and their intent; put private provenance outside the public repository.
- This is separate from the unresolved plant episode parity work.

## Completion

Preserved the three tasks and moved their source identifiers, evidence paths, and suggestion provenance to private reports. The complete tracked-tree check found another affected note added after the original report. Renamed that task to `2026-10-29-eggshell-isolate-remaining-oracle-differences-after-catch-input` and preserved its measurements and open status.

The private publication gate scans all 404 tracked files with zero findings. Only backlog notes changed. No simulation behavior changed. Plant episode parity remains unresolved. Publication must rerun the gate on its final tracked tree.
