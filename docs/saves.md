# Saves

Snapshot version 3 stores the complete integer play state in little-endian
bytes. It includes the level identity, player fields, every bounce pad and
every enemy. A SHA-256 checksum protects the payload. The codec rejects bad
lengths, unsupported versions, wrong level identity and invalid field values.
The current layout is defined by `src/save/snapshot.gd`.

The setting `resume_where_i_left_off` defaults to true. The player loads its
autosave at startup and writes a new one during play and on orderly shutdown.
F5 writes a manual slot and F9 restores it. On a controller, hold the back
button and press the left shoulder to save or the right shoulder to load.

Writes happen on a persistent worker. A write flushes and closes a temporary
file, then renames it within the save directory. It does not synchronize the
file or directory to physical storage. The tests cover process termination,
not sudden power loss. A hard kill can lose the most recent unsaved steps.

Old snapshot versions are ignored with a log message. They are not migrated.
Changing screen shape or graphics does not change snapshot compatibility.
