# issue_window Component

Dependencies: `issue`, `confirm`, `context`.

## Purpose

A floating editor window for modifying issue content. Presents a filtered view of an Issue.md file, showing only user-facing blocks (Issue Description, Issue Resolution, and custom blocks) while hiding internal metadata (Version, Status, Location). Changes are parsed from the buffer and persisted back to the Issue.md file on disk.

## Entry Point

Replaces the `<CR>` keybinding in `show_window`. When the user presses `<CR>` on an issue in the show window:

1. Resolve the issue ID at the cursor line.
2. Deactivate the show window (close the Neovim window but preserve state).
3. Call `issue_window.open(issue_id, { on_dismiss = ..., on_quit = ... })`.

The show window passes two callbacks:
- **on_dismiss**: Re-reads issues from the index and reactivates the show window. If no issues remain, the show window state is discarded.
- **on_quit**: Discards the show window state (sets `active_window = nil`).

The `<C-g>` keybinding inside the issue window provides an escape hatch to open the raw Issue.md file directly.

## Display Format

### Window Title

The window title displays the issue ID and current status:

```
 20260202_163849 [OPEN]
```

### Buffer Content

The buffer contains all blocks from the issue's `blocks` map, rendered as markdown with their H2 headers:

```markdown
## Issue Description
The login form does not validate email format before submission.

## Reproduction Steps
1. Navigate to /login
2. Enter "notanemail" in the email field
3. Click submit — no validation error is shown

## Issue Resolution
Added client-side email regex validation to the form's onSubmit handler.
```

Only blocks that exist on the issue are shown. If the issue has no Issue Resolution block, that section is omitted. Users may create it (or any other block) by typing a new `## ` header.

Block display order:
1. Issue Description (if present)
2. Custom blocks in alphabetical order
3. Issue Resolution (if present) — always last

This display order is independent of the serialization order used by `issue.serialize()`. Since blocks are stored as a map keyed by label, the buffer ordering has no effect on the persisted file format.

The buffer filetype is `markdown`, providing syntax highlighting. The buffer is fully editable.

### Creating New Blocks

Users may create new blocks by adding `## <Label>` lines in the buffer. On save, any new H2 headers are parsed as new block labels and their content is captured.

Constraints:
- Reserved labels (`Version`, `Status`, `Location`) are rejected on save with a warning. Their content is discarded.
- H1 headers (`# `) are not permitted. If found on save, they are logged as a warning and treated as plain text within the enclosing block.
- Empty labels (a bare `## ` with no text after it) are ignored.

## State

```lua
{
  win_id = integer,        -- floating window handle
  buf_id = integer,        -- scratch buffer handle
  issue_id = string,       -- issue ID; used to read the latest issue state from the cache
  on_dismiss = function?,  -- callback when user dismisses back (Esc, C-s)
  on_quit = function?,     -- callback when user quits to vim (C-q, C-g)
}
```

Dirty detection uses `vim.bo[buf_id].modified`. After populating the buffer, `modified` is set to `false`. Any subsequent edits by the user flip it to `true`.

## Mode Handling

The buffer opens in normal mode. The user enters insert mode via standard Vim keys (`i`, `a`, `o`, etc.) when ready to edit.

## Window Configuration

- **Style**: Floating window, centered in the editor
- **Size**: 60% width, 70% height
- **Border**: Rounded, with title (issue ID + status)
- **Buffer options**: `buftype=nofile`, `bufhidden=wipe`, `swapfile=false`, `filetype=markdown`
- **Window options**: `number=false`, `relativenumber=false`, `wrap=true`, `linebreak=true`

## Keybindings

All keybindings are buffer-local, registered on the scratch buffer.

| Key | Modes | Action |
|-----|-------|--------|
| `<C-s>` | n, i | Save changes to disk and dismiss (returns to show window if opened from there) |
| `<C-g>` | n, i | Open the raw Issue.md in the active window (quits to vim) |
| `<C-y>` | n, i | Yank the issue ID to the default register |
| `<Esc>` | n | Dismiss: return to show window if opened from there, otherwise close (confirm if modified) |
| `<C-q>` | n, i | Quit directly to vim, bypassing the show window (confirm if modified) |

`<Esc>` is bound in normal mode only. In insert mode it retains its standard Vim behavior (exit insert mode). This means `<Esc><Esc>` from insert mode returns to the show window: the first `<Esc>` returns to normal mode, the second triggers the dismiss binding.

`<C-s>`, `<C-g>`, `<C-y>`, and `<C-q>` are bound in both normal and insert mode. When triggered from insert mode, the handler calls `vim.cmd("stopinsert")` before proceeding.

`q` is not bound since this is an editable text buffer.

The help line in the footer area adapts to context:

When opened from the show window:
```
 C-s save  Esc back  C-q close  C-g open file  C-y yank id
```

When opened directly (no show window):
```
 C-s save  Esc close  C-g open file  C-y yank id
```

### Save and Close (`<C-s>`)

1. Exit insert mode if active (`stopinsert`).
2. Read all lines from the buffer.
3. Parse into blocks (see [Save Logic](#save-logic)).
4. Validate block labels (warn and discard reserved labels).
5. Read the latest issue state via `issue.read(issue_id)` (picks up any external changes to hidden fields).
6. Replace the issue's `blocks` map with the parsed blocks.
7. Call `issue.write(issue)` to serialize and persist.
8. Capture the `on_dismiss` callback, close the window, then invoke the callback.

When opened from the show window, this returns the user to the show window (which re-reads issues to reflect the saved changes). When opened directly, the window simply closes.

If `issue.read()` fails (e.g., the issue was deleted externally), alert the user via `logger:alert("ERROR", ...)` and close the window. If `issue.write()` fails, alert the user via `logger:alert("ERROR", ...)` and keep the window open so the user does not lose their work.

### Open Raw File (`<C-g>`)

1. Exit insert mode if active (`stopinsert`).
2. If the buffer is modified, show a `caution`-level confirmation dialog ("Discard unsaved changes?").
3. If confirmed (or buffer is not modified):
   a. Resolve the file path via `issue.issue_path(issue_id)`. If this fails, alert the user via `logger:alert("ERROR", ...")` and abort.
   b. Capture the `on_quit` callback, close the window, then invoke the callback (discards show window state if applicable).
   c. Open the resolved path in the editor with `:edit`.

### Dismiss (`<Esc>`)

1. If the buffer is modified, show a `caution`-level confirmation dialog ("Discard unsaved changes?").
2. If confirmed (or buffer is not modified), capture the `on_dismiss` callback, close the window, then invoke the callback.

When opened from the show window, this returns the user to the show window. When opened directly, the window simply closes.

### Quit (`<C-q>`)

1. Exit insert mode if active (`stopinsert`).
2. If the buffer is modified, show a `caution`-level confirmation dialog ("Discard unsaved changes?").
3. If confirmed (or buffer is not modified), capture the `on_quit` callback, close the window, then invoke the callback.

Always closes directly to vim, bypassing the show window regardless of how the issue window was opened.

## Save Logic

When `<C-s>` is pressed, the buffer is parsed back into blocks:

1. Read all lines from the buffer.
2. Split on lines matching `^## (.+)$` to identify block boundaries.
3. For each block:
   - The text after `## ` is the block label.
   - All lines between this header and the next `## ` (or end of buffer) are the block content.
   - Trim leading and trailing blank lines from each block's content.
4. Discard blocks with reserved labels (`Version`, `Status`, `Location`) and log a warning for each.
5. Discard content that appears before the first `## ` header (if any).
6. Read the latest issue state via `issue.read(issue_id)`.
7. Replace the issue's `blocks` map entirely with the parsed result.
8. Serialize and write via `issue.write(issue)`.

The hidden fields (version, status, location) are read fresh from the issue module's cache at save time, ensuring they reflect the latest on-disk state. The buffer content only affects the `blocks` map. The `issue.serialize()` function handles placement of hidden fields in the output.

## External Modification

No automatic refresh is implemented. The window shows a snapshot of the issue at open time. If the file is modified externally while the window is open, the save operation will overwrite external changes. This is acceptable because:

- The window is intended for short-lived editing sessions.
- External modification while the window is open is unlikely.
- The `<C-g>` escape hatch provides full file access for complex scenarios.

## Public API

### issue_window.open(issue_id, opts?)

Opens the floating editor window for the given issue ID. Reads the issue via `issue.read(issue_id)` to get the latest state from the cache, then populates the buffer with the user-facing blocks.

`opts` is an optional table:
- `on_dismiss`: `function?` — called after the window closes via `<Esc>` or `<C-s>`. The show window uses this to reactivate itself.
- `on_quit`: `function?` — called after the window closes via `<C-q>` or `<C-g>`. The show window uses this to discard its state.

If `issue.read()` fails, the user is alerted via `logger:alert("ERROR", ...)` and the window is not opened. If the window is already open, focuses it instead of creating a duplicate.

### issue_window.close()

Closes the floating window and cleans up all state, including the `on_dismiss` and `on_quit` callbacks. Does not check for unsaved changes — callers are responsible for dirty confirmation before calling close.

### issue_window.is_open()

Returns `true` if the issue window is currently open and valid.

## Autocmds

- **WinClosed**: Clean up module state when the window is closed externally (e.g., `:q`). No dirty confirmation in this path — the user explicitly closed the window via Neovim's own mechanism.
- **VimResized**: Recalculate window dimensions and reposition.

## Changes to Existing Components

### show_window

The `<CR>` keybinding is updated. Instead of opening the raw Issue.md via `:edit`, it:

1. Resolves the issue ID at the cursor line.
2. Deactivates the show window (closes the Neovim window but preserves state including `active_window`, issues, filter, etc.).
3. Calls `issue_window.open(issue_id, { on_dismiss = ..., on_quit = ... })`.

The `on_dismiss` callback re-reads issues from the index (via `Window:reload_issues()`) and reactivates the show window. If no issues remain after the re-read, the show window state is discarded instead.

The `on_quit` callback discards the show window state (`active_window = nil`).

A new `Window:reload_issues()` method is extracted from `Window:refresh()`. It re-reads issues from the index and updates `self.issues` without requiring a valid buffer or window. Returns `false` if no issues remain. `Window:refresh()` delegates to `reload_issues()` for the data portion, then renders and clamps the cursor.
