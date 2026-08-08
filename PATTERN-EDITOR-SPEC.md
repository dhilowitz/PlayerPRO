# Pattern Editor — behaviour of the classic PlayerPRO editor

Derived by reading the original Carbon implementation, which lives in the
legacy tree at `Files/wds_editors/Editor.c` (4,556 lines), `Files/Partition.c`,
and `Files/Main.c`. This is a specification for reimplementing
`ClassicalViewController`, which is currently an empty Xcode template.

> Note on reading the originals: they are MacRoman with CR line endings, so
> `grep` treats them as binary and silently finds nothing. Convert first:
> `tr '\r' '\n' < Editor.c | iconv -f MACINTOSH -t UTF-8`

## The data model already exists

Nothing here requires engine work. `PPMusicObject` → `patterns` →
`PPPatternObject` → commands is complete in PlayerPROKit, and saving is
verified working (load → modify → save → reload produces a valid MADK).

A cell is one `Cmd`, six bytes:

| Field | Meaning | Empty value |
|---|---|---|
| `ins` | instrument number | `0` |
| `note` | note, 0…95 | `0xFF` |
| `cmd` | effect command | `0` |
| `arg` | effect argument | `0` |
| `vol` | volume | `0xFF` |

"Empty" matters: the Delete operation writes exactly
`ins=0, note=0xFF, cmd=0, arg=0, vol=0xFF`.

## Grid

Rows are positions in the pattern (`pattern.header.size`, usually 64).
Columns are tracks (`header->numChn`). Selection is a **rectangle** over
(track, position), not a single cell — `myList.select` is a `Rect` with
`left`/`right` in tracks and `top`/`bottom` in rows.

### Cell rendering

From `CreateNoteString()`. Each sub-field is independently toggleable through
preferences (`thePrefs.DigitalInstru`, `DigitalNote`, and siblings), and each
renders as a fixed 3-character group separated by single spaces:

- instrument — 3 chars from the `EInstru` table, or 3 spaces when `ins == 0`
- note — 3 chars from the `ENote` table, or 3 spaces when `note == 0xFF`
- then volume, effect and argument on the same pattern

The cell being edited swaps its 3-character group for live text-field content,
so the grid renders the in-progress edit rather than the stored value.

## Keyboard

Raw character codes as the original tested them.

### Navigation

| Key | Code | Behaviour |
|---|---|---|
| Up | `0x1E` | move up by `curStep` |
| Down | `0x1F` | move down by `curStep` |
| Left | `0x1C` | previous track |
| Right | `0x1D` | next track |
| Return / Enter | `0x0D` / `0x03` | apply **Fill**, flash the Fill button, then advance by `curStep` |

`curStep` is the tracker "step" value — entry and vertical movement advance by
it, not by one row.

Horizontal movement wraps within the pattern: `h < 0` → last track,
`h >= maxX` → track 0.

### Vertical wrap crosses patterns

This is the subtle part. On running past the top or bottom, if
`MADDriver->JumpToNextPattern` is set and `thePrefs.patternWrapping` is false,
the editor steps to the previous/next entry in the **order list** and follows
it to a different pattern:

```
newPL--/++  →  clamp at the ends  →  Pat = oPointers[PL]
```

Otherwise the row index simply wraps inside the current pattern. Both paths
reset `MADDriver->Pat`.

### Selection

Shift + arrow extends the selection rectangle rather than moving the cursor:

| Key | Effect |
|---|---|
| Shift+Up | `rect.top--` |
| Shift+Down / Shift+Return | `rect.bottom++` |
| Shift+Left | `rect.left--` |
| Shift+Right | `rect.right++` |

Select All selects `(0, 0)` to `(numChn, pattern.header.size)`.

### Editing

| Key | Effect |
|---|---|
| `/` | transpose selection down one semitone (`note--`, floor 0) |
| `*` | transpose selection up one semitone (`note++`, ceiling `NUMBER_NOTES-1`) |
| Delete | clear every cell in the selection to the empty values above |

Both operate over the whole selection rectangle, set `curMusic->hasChanged`,
and push an undo entry first (see below).

### Note entry

`thePrefs.MacKeyBoard` gates typing-as-notes. The map is **user-remappable**,
not hardcoded — `ConvertCharToNote()` is a 256-entry lookup:

```c
i = thePrefs.PianoKey[theChar];
if (i != 0xFF && i != -1) i += thePrefs.pianoOffset * 12;
```

- `-1` — unmapped, key ignored
- `0xFF` — passed through as a distinct value (key-off)
- `pianoOffset` shifts by whole octaves

`Help.c` contains the UI for reassigning keys, so **remapping is a feature to
preserve, not an incidental detail**. The default table ships in a preferences
resource rather than in code; the practical way to recover it is to read it out
of a running copy of the legacy app.

Entry runs through `DigitalEditorProcess(whichNote, …)` and only applies when
record mode (`EditorKeyRecording`) is on. It writes the note, then writes each
of the other fields **only if its toggle is enabled**:

| Toggle | Writes |
|---|---|
| `OnOffInstru` | `ins = curInstru` |
| `OnOffFX` | `cmd = DefaultFX` |
| `OnOffArg` | `arg = DefaultArg` |
| `OnOffVolume` | `vol = DefaultVol`, or `0xFF` when that default is 0 |

Then advance by `curStep`, applying the same cross-pattern wrap as navigation.

Typing also auditions the note live through
`DoPlayInstruInt(i, ins, eff, arg, volCmd, &MADDriver->chan[track], 0, 0)`, and
highlights the key in the on-screen piano and Mozart views.

## Clipboard

The unit is `Pcmd` — a rectangular block, not a flat list:

```c
myPcmd->tracks     = select.right  - select.left + 1;
myPcmd->length     = select.bottom - select.top  + 1;
myPcmd->trackStart = select.left;
myPcmd->posStart   = select.top;
// followed by tracks * length contiguous Cmd records
```

`ConvertPcmd2Text()` also renders a selection as text — cells tab-separated
across tracks, CR at end of row, empty cells as 14 spaces. Worth keeping: it is
what makes pattern data pasteable into a text editor and back.

## Undo

Every mutating operation calls `SaveUndo(UPattern, CurrentPat, "…")` **before**
touching data, with a human-readable label that reaches the Edit menu, e.g.
`Undo 'Change Note in Digital Editor'`, `Undo 'Delete Digital Editor'`,
`Undo 'Key Press in Digital Editor'`. Granularity is the whole pattern.

## Redraw

The original is careful about invalidation, and a reimplementation should be
too — the grid is large and redrawn constantly during playback:

- `UPDATE_Note(v, h)` — single cell
- `UPDATE_NoteBOUCLE(v, h)` / `UPDATE_NoteFINISH()` — batch, called per cell
  inside a loop and then finished once
- `PLAutoScroll()` — scroll the cursor back into view after any move
- `PLGetSelectRect()` intersected with the visible rect, then
  `InvalWindowRect` — only the visible part of a changed selection is
  invalidated

When `thePrefs.MusicTrace` is on, the playing position drives
`MADDriver->PartitionReader`, so the grid follows playback.

## Suggested build order

1. Read-only grid: draw a pattern, correct cell formatting, scrolling.
2. Cursor and rectangular selection, including the shift-arrow extensions.
3. Note entry with `curStep` advance and the field toggles.
4. Delete and transpose over a selection, with undo.
5. `Pcmd` copy/paste, then the text representation.
6. Cross-pattern wrap and playback tracing.

Steps 1–4 are already a usable tracker.
