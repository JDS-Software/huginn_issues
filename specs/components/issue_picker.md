# issue_picker Component

Dependencies: `issue` (for display formatting), `context` (for configuration).

## Purpose

A lightweight floating window for selecting a single issue from a list. Used by `HuginnAdd` and `HuginnRemove` to let the user choose which issue to modify. The picker displays only the issues provided via `opts.issues` — callers are responsible for pre-filtering by location eligibility before opening the picker. This is the inverse of `show_window`, which uses an `is_relevant` predicate to include issues matching the cursor location; here, the calling command excludes issues based on the cursor's references (see `add_and_remove.md` step 7 for each command's criteria). Both open and closed issues from the filtered set are presented, with status displayed inline.

## Public API

### issue_picker.open(opts, callback)

Opens a centered floating window displaying the provided issues. Calls `callback(issue_id)` when the user selects an issue, or `callback(nil)` on dismissal.

`opts` is a table:

```lua
---@class huginn.IssuePickerOpts
{
  issues = HuginnIssue[],         -- issues to display
  header_context = string,        -- pre-formatted header string (action + scope + filepath)
  context = huginn.CommandContext, -- command context (provides config for description_length)
}
```

No-ops if `callback` is missing or not a function. Calls `callback(nil)` if `opts` is invalid or `issues` is empty.

If the window is already open, focuses it instead of creating a duplicate.

### issue_picker.close()

Closes the floating window and cleans up state. Does not fire the callback — callers that need dismissal notification should use the callback from `open`.

### issue_picker.is_open()

Returns `true` if the picker window is currently open and valid.

## Display Format

### Header Line

The first line of the buffer displays the action context and active filter:

```
Add: src/math.lua > calculate                      [Filter: ALL]
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

Columns follow the same format as `show_window`:
1. **Issue ID**: `yyyyMMdd_HHmmss` format, left-aligned, fixed width 16.
2. **Status**: `[OPEN]` or `[CLOSED]`, left-aligned, fixed width 9.
3. **Description**: Obtained via `issue.get_ui_description(cmd_ctx, issue)`, which truncates at the first period, first newline, or `config.show.description_length`, whichever is shortest; appends `...` if truncated by length cap; returns `(no description)` if empty or missing. Fills remaining width.

### Footer

A separator and centered help line showing available keyboard shortcuts:

```
────────────────────────────────────────────────────
          Enter select  q cancel  C-f filter
```

The footer is non-selectable — the cursor is clamped to issue lines only.

## State

The component maintains the following state while the window is open:

```lua
{
  win_id = integer,                    -- floating window handle
  buf_id = integer,                    -- scratch buffer handle
  issues = HuginnIssue[],              -- full issue objects passed via opts
  display_issues = table[],            -- filtered subset currently displayed
  line_map = table<integer, string>,   -- maps buffer line number -> issue ID
  filter = "all" | "open" | "closed", -- current filter state
  header_context = string,             -- pre-formatted header string
  callback = function,                 -- selection callback
}
```

## Window Configuration

- **Style**: Floating window, centered in the editor
- **Size**: 80% width, height sized to content (header + separator + issue lines + footer), capped at 50% height. When the content exceeds the cap, the window is scrollable. Minimum height accommodates header, separator, one issue line, and footer.
- **Buffer options**: `buftype=nofile`, `bufhidden=wipe`, `modifiable=false`, `swapfile=false`
- **Window options**: `cursorline=true`, `number=false`, `relativenumber=false`
- **Cursor**: Initialized to line 3 (first issue line). Clamped to issue lines only (cannot enter header/separator or footer).

## Keybindings

All keybindings are buffer-local, registered on the scratch buffer.

| Key | Action |
|-----|--------|
| `<CR>` | Select the highlighted issue |
| `q` | Cancel (callback receives `nil`) |
| `<Esc>` | Cancel (callback receives `nil`) |
| `<C-f>` | Cycle filter: all -> open -> closed -> all |

### Select Issue (`<CR>`)

1. Resolve the issue ID at the current cursor line via `line_map`. If `line_map` has no entry for the current line (e.g., the filtered list is empty), no-op.
2. Close the window.
3. Call `callback(issue_id)`.

### Cancel (`q` / `<Esc>`)

1. Close the window.
2. Call `callback(nil)`.

### Cycle Filter (`<C-f>`)

Advances the filter: `"all"` -> `"open"` -> `"closed"` -> `"all"`. Re-renders issue lines based on the active filter and updates the header line's filter label. Resets the cursor to the first issue line. If the filtered list is empty, a centered `(no issues match filter)` message is shown in place of issue lines and the cursor is clamped to the placeholder line.

## Double-Fire Guard

A `resolved` flag prevents the callback from firing more than once. Both select and cancel check this flag before proceeding. This follows the same pattern as the `prompt` component.

## Autocmds

- **CursorMoved**: Clamp cursor to issue lines only (line 3 through the last issue line, excluding footer). When the filtered list is empty, clamp to the placeholder line.
- **WinClosed**: Clean up module state when the window is closed externally (e.g., `:q`). If the callback has not yet fired, calls `callback(nil)`. Cleans up the augroup.
- **VimResized**: Recalculate window dimensions and reposition.
