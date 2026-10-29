# Backlog storage

Tracked `.forgerie/backlog/*.md` cards contain neutral task summaries, public
code paths, acceptance checks, and status. They must not contain private source
names, sample identifiers, source locations, or copied technical evidence.
Keep the filename and frontmatter `id` stable when editing a card.

Store detailed evidence outside this repository, in the private repository or
`~/.local/share/eggshell-run/`. Before removing evidence from a tracked card,
save its exact original bytes there and verify the backup. Record the card ID,
source revision, and SHA-256 hash with the backup. Keep a private mapping if an
existing ID itself requires a source-neutral replacement. Never put the old
private ID in a public redirect or commit message.

## Existing evidence

The four cards cleaned in commit `cac7092` have exact original copies under
`~/.local/share/eggshell-run/backlog-publication-cleanup/original-notes/`.
The sibling `report.md` maps current card IDs to original IDs and evidence
locations. The sibling `before.json` records the source revision and hashes.
Three original IDs remain unchanged. The fourth has a neutral replacement,
with its original identity preserved in that private mapping.

Use the current card ID to find its entry in `report.md`, then read its original
note and the referenced reports. Do not copy those details back into tracked
cards. This lookup requires access to the local artifact directory. A public
checkout alone does not contain the private evidence.

## Publication check

Run the unchanged private publication gate on the complete tracked tree,
including backlog files and commit messages in the publication range. Stage
new public files before the check so the gate includes them. Do not exclude
backlog metadata or relax the denylist to pass publication.

A passing tree check does not sanitize earlier commits or other local branches.
Do not push local research history as part of a backlog cleanup. Rerun the gate
on the exact final publication tree.
