# Menus and level list

The pause menu, the settings page and the level list draw with the default font
at 16 pixels, white on black, inside a one-pixel white border. This is the
message panel's style. The menus add no images. The menu is a view: it reads
play state and never writes it.

## Pause

Escape, P or the controller Start button opens the menu during play. While the
menu is open, no simulation step runs, so play state does not change. Snapshot
bytes before and after the menu are equal (`tests/menu_pause.gd`). Sound pauses
with the simulation. After a goal the completion music keeps playing.

Closing the menu does not send the confirm press to play. A button that is held
when the menu closes reaches the simulation only after the player releases it.

## Pages

| Page | Items |
| --- | --- |
| Paused | Resume, Restart level, Save to slot, Load from slot, Levels (with a folder), Settings, Quit |
| Level complete | Next level (with a folder, when a later level exists), Restart level, Save to slot, Load from slot, Levels, Settings, Quit |
| Settings | Zoom, Music volume, Effects volume, Quick death, Play timer, Resume where I left off, Back |
| Levels | One row for each file in the folder |
| Start | Levels, Settings, Quit; shown with a folder and no open level |

The Level complete page opens by itself when the player reaches the goal. It
shows the score, the total time, hits and deaths. Replays and screenshot runs do
not open it.

- **Restart level** starts the level again from its beginning, as a fresh load does.
- **Save to slot** and **Load from slot** use the manual slot (F5 and F9).
  Load closes the menu. Without a saved slot the menu says so and stays open.
- **Quit** saves the autosave (when that setting is on) and closes the game.

## Controls

| Action | Keyboard | Controller |
| --- | --- | --- |
| Open the menu | Escape or P | Start |
| Move the focus | Up/Down or W/S | D-pad or left stick |
| Change a value | Left/Right or A/D | D-pad or left stick |
| Select | Enter, Space or Z | A (lower face button) |
| Back | Escape, Backspace or X | B (right face button) |
| Close the menu | P | Start |
| Page through a list | Page Up / Page Down | Left / right shoulder |

Back on the Paused page resumes play. Arrow keys repeat while held; one stick
push moves the focus once. A mouse click on a row selects it; on a value row,
the left half lowers the value and the right half raises it. The mouse wheel
scrolls the list.

## Settings

Each change is saved at once in `settings.json`. See [saves](saves.md#slots-and-writes).

| Setting | Values | Effect |
| --- | --- | --- |
| Zoom | Whole steps within the window's limits | The same zoom as the `=` and `-` keys |
| Music volume | 0 to 100 in steps of 10 | Applies at once |
| Effects volume | 0 to 100 in steps of 10 | Applies at once |
| Quick death | On or off (default off) | After a death, skip the 4-second wait and fade out in half a second |
| Play timer | On or off (default off) | Shows three clocks in the lower left corner |
| Resume where I left off | On or off (default on) | Load the autosave when a level opens and write autosaves |

Quick death is the saved player field `quick_death`. The game copies the setting
into play state just before the next step, never while the menu is open. Replays
keep the value in their state. The play timer shows:

| Clock | Meaning |
| --- | --- |
| Attempt | Time since the last start or respawn |
| Level | Level time; a respawn returns it to the time at the last checkpoint |
| Total | All play time in this run, across deaths |

Clocks count only during active play.

## Level list

`--levels=DIR` (after the argument separator) opens a folder of level-code
files. The list holds every `.json` and `.txt` file directly in the folder, in
natural file-name order, up to 4096 files. Each row shows the level name and
the author from the level code. A level without a name shows its file name.
A file that is not a level code stays in the list, dimmed, with the reason.
Selecting it shows the reason and opens nothing.

The list only chooses a file. The game reads and builds the chosen level with
the same path as `--level-code`, and a level that does not build shows its error
in the menu. With `--levels` alone, the game opens at the list. With
`--level-code` as well, that level opens first, and the list marks it as playing
when the file is in the folder. After a goal, Next level opens the next readable
file in the folder.

With a folder, each level has its own autosave and manual slot in
`levels/<level identity>/` under the save directory. The level identity is the
SHA-256 of the level code. Without a folder, the files stay at the top of the
save directory, as before.

## Layout

The menu is a function of the window size only (`MenuView.plan`). It draws at a
whole-number scale: 1 up to twice the 832 by 448 reference size, then 2, 3 or 4.
It never draws below scale 1, so text stays 16 pixels high. The panel is at most
480 pixels wide (unscaled) for a readable line length. Its height follows its
content up to the window height. Margins shrink before the panel does.

Rows wrap long names instead of cutting them. A list longer than the panel
scrolls: the cut-off row and the scroll bar show that more exists, and the
focused row always scrolls into view. When the list area would keep fewer than
four rows, the folder line and the key hint move into the scrolling list, so a
short window keeps more rows on the surface. Every item stays reachable at
every size.

The play timer reflows the same way: three rows while they fit in a quarter of
the window height, else one row. Only when neither fits does it draw smaller,
by halves, so in a very small window it can become hard to read.
