# show_window Component

Dependencies: `issue`, `issue_index`, `annotation`, `location`.

## Purpose

A floating window component that displays a list of issues for a source file. Supports filter cycling, status toggling, and issue deletion via keyboard shortcuts. Similar in structure to the `log_viewer` component but with interactive issue management.

## Display Format

### Header Line

The first line of the buffer displays the cursor context and active filter:

```
<relative_filepath> > <symbol>                    [Filter: ALL]
```

If the cursor was not in a named scope when the command was invoked:

```
<relative_filepath>                               [Filter: ALL]
```

The filter label cycles through: `ALL`, `OPEN`, `CLOSED`.

The header line is non-selectable — the cursor is clamped to issue lines (line 3 onward).

### Separator

A horizontal rule on line 2:

```
────────────────────────────────────────────────────
```

### Issue Lines

Starting from line 3, one line per issue:

```
20260201_205126  [OPEN]   Testing huginn_create
20260201_220036  [CLOSED] Testing
20260202_141823  [OPEN]   We need a second issue...
```

Columns:
1. **Issue ID**: `yyyyMMdd_HHmmss` format, left-aligned, fixed width 16.
2. **Status**: `[OPEN]` or `[CLOSED]`, left-aligned, fixed width 9.
3. **Description**: Truncated per the rules in [spec_show.md](spec_show.md#description-truncation). Fills remaining width.

### Footer

A separator and centered help line showing available keyboard shortcuts:

```
────────────────────────────────────────────────────
          Enter open  q close  C-f filter  C-r resolve/reopen  C-d delete
```

The footer is non-selectable — the cursor is clamped to issue lines only.

## State

The component maintains the following state while the window is open:

```lua
{
  win_id = integer,                    -- floating window handle
  buf_id = integer,                    -- scratch buffer handle
  issues = HuginnIssue[],              -- full issue objects (for mutations)
  display_issues = table[],            -- filtered subset currently displayed
  line_map = table<integer, string>,   -- maps buffer line number -> issue ID
  filter = "all" | "open" | "closed", -- current filter state
  source_filepath = string,            -- relative filepath of the source file
  source_bufnr = integer,             -- buffer number of the source file
  header_context = string,             -- formatted header string
  config = table,                      -- active config reference
}
```

## Window Configuration

- **Style**: Floating window, similar to `log_viewer`
- **Size**: 80% width, 50% height (or smaller if few issues)
- **Buffer options**: `buftype=nofile`, `bufhidden=wipe`, `modifiable=false`, `swapfile=false`
- **Window options**: `cursorline=true`, `number=false`, `relativenumber=false`
- **Cursor**: Initialized to line 3 (first issue line). Clamped to issue lines only (cannot enter header/separator or footer).

## Keybindings

All keybindings are buffer-local, registered on the scratch buffer.

| Key | Action |
|-----|--------|
| `<CR>` | Open the highlighted issue's `Issue.md` file |
| `q` | Close the window |
| `<Esc>` | Close the window |
| `<C-r>` | Resolve or reopen the highlighted issue |
| `<C-d>` | Delete the highlighted issue (with confirmation) |
| `<C-f>` | Cycle filter: all -> open -> closed -> all |

A centered help line showing these shortcuts is displayed in the footer below the issue list.

### Open Issue (`<CR>`)

Deactivates the show window (closes the Neovim window but preserves state) and opens the issue in `issue_window`. Two callbacks are passed:

- **on_dismiss**: Re-reads issues from the index via `Window:reload_issues()` and reactivates the show window. If no issues remain, discards the show window state.
- **on_quit**: Discards the show window state (`active_window = nil`).

This allows the user to return to the show window by pressing `<Esc>` in the issue window, or close directly to vim with `<C-q>`.

### Resolve / Reopen (`<C-r>`)

For OPEN issues, prompts for a resolution description via the `prompt` component, then delegates to `issue.resolve(id, description)`. For CLOSED issues, delegates to `issue.reopen(id)` immediately. Refreshes the display and source buffer annotations after either operation.

### Delete Issue (`<C-d>`)

Delegates to `issue.delete(id, callback)`, which owns the confirmation dialog. On successful deletion the display is refreshed and source buffer annotations are updated. If no issues remain, the window closes.

### Cycle Filter (`<C-f>`)

Advances the filter: `"all"` -> `"open"` -> `"closed"` -> `"all"`. Re-renders issue lines and resets the cursor to the first issue line. If the filtered list is empty, a centered `(no issues match filter)` message is shown.

## Refresh

The `refresh()` internal function:

1. Re-read the IndexEntry via `issue_index.get(source_filepath)`.
2. Re-read all issues via `issue.read(id)` for each ID in the index.
3. Apply current filter.
4. Rebuild `display_issues` and `line_map`.
5. Set buffer `modifiable=true`, replace all lines, set `modifiable=false`.
6. Adjust cursor: if current line exceeds new line count, move to last issue line.
7. If no issues remain (index empty or all filtered out after deletion), close the window.

## Public API

### show_window.open(opts)

Opens the floating window. `opts` contains:
- `issues`: `HuginnIssue[]` — full issue objects
- `header_context`: `string` — pre-formatted header context (filepath > symbol)
- `source_filepath`: `string` — relative path for re-querying the index
- `source_bufnr`: `integer` — source buffer for annotation refresh
- `config`: `table` — active configuration
- `is_relevant`: `fun(iss: HuginnIssue): boolean` — predicate applied during `refresh()` to re-filter issues after re-reading from the index. File-scoped issues and issues with references overlapping the cursor location return `true`; others are excluded.

If the window is already open, focuses it instead of creating a duplicate.

### show_window.close()

Closes the floating window and cleans up state.

## Autocmds

- **WinClosed**: Clean up state when the window is closed externally (e.g., `:q`).
- **VimResized**: Recalculate window dimensions and reposition, similar to `log_viewer`.
