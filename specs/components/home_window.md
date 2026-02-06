# home_window Component

Dependencies: `issue`, `issue_index`, `location`.

## Purpose

A floating window component that displays all project files with issues. Supports filter cycling (ALL/OPEN/CLOSED), a persistent fuzzy filter input line (telescope-style), keyboard navigation with a selection highlight, and auto-expanding accordion to view individual issues under the selected file. The cursor lives on the input line while a separate extmark-based highlight tracks the selected row.

## Display Format

### Header Line

```
HuginnHome                                        [Filter: ALL]
```

The filter label cycles through: `ALL`, `OPEN`, `CLOSED`.

### Separator

A horizontal rule on line 2:

```
────────────────────────────────────────────────────
```

### File Entry Lines

Starting from line 3, one line per file that has matching issues:

```
src/commands/show.lua  (3)
src/modules/issue.lua  (5)
lua/huginn/init.lua  (1)
```

Each line shows the relative filepath and the count of issues matching the active filter in parentheses. Files with zero matching issues for the current filter are hidden. Entries are sorted alphabetically by filepath.

### Expanded Issue Lines

The currently selected file is automatically expanded, showing its individual issues as indented lines directly below the parent file entry. Only one file can be expanded at a time (accordion behavior). When the selection moves to a different file, it auto-expands and the previous file collapses.

```
src/commands/show.lua  (3)
  Fix null check  (fn:process_data)
  Handle edge case  (fn:validate)
  Missing return  (fn:process_data)
src/modules/issue.lua  (5)
lua/huginn/init.lua  (1)
```

Each issue line is indented with two spaces and shows:
- The issue description (via `issue.get_ui_description()`).
- The reference in parentheses, formatted as `type:symbol` from the first entry of `issue.location.reference`. If the issue has no location or no reference, the parenthetical is omitted.

Issue lines respect the active filter — only issues whose status matches the current filter are shown. Issues are sorted by ID (chronological).

### No Matches Placeholder

When no files match the current filter + query combination, a centered placeholder is shown:

```
                    (no files match)
```

### Footer

A separator, a centered help line, and a fuzzy filter input line:

```
────────────────────────────────────────────────────
    Enter open  q close  C-f filter  C-n/C-p/arrows navigate
>
```

The last line is the input line. The `>` prompt character is always present. User typing appears after it and triggers fuzzy filtering of the entry list.

## State

The component maintains the following state while the window is open:

```lua
{
  win_id = integer,                      -- floating window handle
  buf_id = integer,                      -- scratch buffer handle
  entries = map<string, IndexEntry>,     -- full entries from issue_index.all_entries()
  display_entries = table[],             -- filtered/sorted subset: { filepath, count }
  visible_rows = table[],               -- flat list of rendered rows (see Visible Rows)
  line_map = table<integer, VisibleRow>, -- maps buffer line number -> VisibleRow
  filter = "all" | "open" | "closed",   -- current filter state
  query = string,                        -- current fuzzy filter text
  selected_index = integer,              -- 1-based index into visible_rows
  expanded_filepath = string | nil,      -- filepath of the currently expanded file, or nil
  expanded_issues = table[],             -- loaded issue data for the expanded file
  context = CommandContext,              -- command context
  ns_id = integer,                       -- namespace ID for selection highlight extmark
}
```

### VisibleRow

Each entry in `visible_rows` is one of two types:

```lua
-- A file row
{ type = "file", filepath = string, count = integer }

-- An issue row (only present when the parent file is expanded)
{ type = "issue", filepath = string, issue_id = string, description = string, reference = string | nil }
```

## Window Configuration

- **Style**: Floating window with rounded border
- **Size**: 80% width, height fits content capped at 50% of editor height
- **Buffer options**: `buftype=nofile`, `bufhidden=wipe`, `swapfile=false`
- **Window options**: `cursorline=false` (selection is managed via extmark highlight), `number=false`, `relativenumber=false`
- **Height calculation**: 2 header lines + visible rows (min 1) + 3 footer lines (separator + help + input) = `max(#visible_rows, 1) + 5`, capped at 50% of editor height. This accounts for expanded issue lines when a file is open.
- **Border title**: ` Huginn Home `
- **Cursor**: Initialized on the input line (last line of buffer). Insert mode activated via `startinsert`.

## Cursor Management

The cursor is clamped to the input line (last line of the buffer) via `CursorMoved` and `CursorMovedI` autocmds. The user never moves the cursor to entry lines directly — instead, `C-n`/`C-p` move the `selected_index` and update the extmark-based selection highlight.

## Selection Highlight

Since `cursorline` is disabled (the cursor is on the input line, not on entries), the selected row is highlighted using `nvim_buf_add_highlight` with the `CursorLine` highlight group. The `apply_selection_highlight()` method:

1. If `#visible_rows == 0`, clear the namespace and return (nothing to highlight).
2. Clears the namespace (`ns_id`) to remove the previous highlight.
3. Computes the buffer line for the current `selected_index`: `line = selected_index + 1` (0-based buffer line = 1-based index - 1 + 2 header lines). This works directly because `visible_rows` is a flat list that maps 1:1 to rendered entry lines.
4. Applies `nvim_buf_add_highlight` on that line with hl group `CursorLine`.

## Fuzzy Matching

The fuzzy match function checks whether all characters in the query appear in order within the filepath, case-insensitive:

```lua
local function fuzzy_match(str, query)
    if query == "" then return true end
    local lower_str = str:lower()
    local lower_query = query:lower()
    local si = 1
    for qi = 1, #lower_query do
        local ch = lower_query:sub(qi, qi)
        local found = lower_str:find(ch, si, true)
        if not found then return false end
        si = found + 1
    end
    return true
end
```

## Filter Cycling

The filter cycles: `"all"` -> `"open"` -> `"closed"` -> `"all"`.

When the filter changes:
1. Set `expanded_filepath = nil`, `expanded_issues = {}`.
2. `build_display_entries()` is re-run with the new filter and current query.
3. Files with zero matching issues are hidden.
4. Issue counts per file update to reflect only matching issues.
5. `build_visible_rows()` is re-run.
6. `selected_index` resets to 1.
7. Call `update_expansion()` to auto-expand the first file.
8. The buffer is re-rendered.

### count_matching_issues(entry, filter)

Counts issues in an IndexEntry matching the filter. Note that `entry.issues` is a `map<string, string>` (not a sequence), so counting requires iterating pairs rather than using `#`.

- `"all"`: total number of issues (count all pairs).
- `"open"`: count of issues with status `"open"`.
- `"closed"`: count of issues with status `"closed"`.

### build_display_entries(entries, filter, query)

1. For each `(filepath, entry)` pair, compute `count_matching_issues(entry, filter)`.
2. Skip entries where count is 0.
3. Apply `fuzzy_match(filepath, query)` — skip non-matching.
4. Collect into a list of `{ filepath = fp, count = n }`.
5. Sort alphabetically by filepath.
6. Return the list.

### build_visible_rows(display_entries, expanded_filepath, expanded_issues)

Produces the flat `visible_rows` list from `display_entries` and the current expansion state.

1. Initialize an empty list.
2. For each entry in `display_entries`:
   a. Append a file row: `{ type = "file", filepath = entry.filepath, count = entry.count }`.
   b. If `entry.filepath == expanded_filepath`, append one issue row per item in `expanded_issues`:
      `{ type = "issue", filepath = entry.filepath, issue_id = iss.id, description = iss.description, reference = iss.reference }`.
3. Return the list.

### load_expanded_issues(filepath, entry, filter, context)

Loads full issue data for the issues belonging to `filepath`. Called by `update_expansion()` when the selected file changes.

1. Collect issue IDs from `entry.issues` that match the current `filter` (all, open, or closed).
2. Sort the matching IDs alphabetically (chronological, since IDs are `yyyyMMdd_HHmmss`).
3. For each ID, call `issue.read(id)` to load the full issue. If `issue.read` returns an error, alert via `context.logger:alert("WARN", "Failed to read issue " .. id .. ": " .. err)` and return an empty list.
4. For each loaded issue, build a row entry:
   - `id`: the issue ID.
   - `description`: `issue.get_ui_description(context, iss)`.
   - `reference`: If `iss.location` and `iss.location.reference` are non-empty, format the first entry as `type:symbol` (split on `|`). Otherwise `nil`.
5. Return the list of row entries. This list is stored in `self.expanded_issues`.

## Keybindings

All keybindings are buffer-local, registered on the scratch buffer. Mapped in both insert and normal mode unless noted.

| Key | Mode | Action |
|-----|------|--------|
| `<CR>` | insert, normal | Open the selected file, or navigate to the selected issue's location |
| `q` | normal | Close the window |
| `<Esc>` | normal | Close the window |
| `<C-f>` | insert, normal | Cycle filter: all -> open -> closed -> all |
| `<C-n>` / `<Down>` | insert, normal | Move selection down (wraps around) |
| `<C-p>` / `<Up>` | insert, normal | Move selection up (wraps around) |

### Open / Navigate (`<CR>`)

If `#visible_rows == 0`, return (no-op).

Behavior depends on the type of the selected row (`visible_rows[selected_index]`):

**File row**: Close the home window and open the file via `vim.cmd("edit " .. vim.fn.fnameescape(absolute_path))`, where `absolute_path` is computed by joining `context.cwd` with the row's filepath.

**Issue row**: Close the home window, open the file (same as above using the row's filepath), then navigate to the issue's source location:
1. Call `issue.read(row.issue_id)` to load the full issue.
2. If the issue has no location, stop (file is already open).
3. Call `location.resolve(context.cwd, iss.location)` to resolve references via tree-sitter.
4. For the first reference with `result == "found"` and a non-nil `node`, get the position via `node:range()` (returns 0-based row/col).
5. Set the cursor via `vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })`.

### Auto-Expand

`update_expansion()` is called after any operation that changes `selected_index`. It ensures the selected file is always expanded (accordion behavior).

1. If `#visible_rows == 0`, return.
2. Get the current row: `visible_rows[selected_index]`.
3. Determine the target filepath:
   - If the row is a file row, use `row.filepath`.
   - If the row is an issue row, use `row.filepath` (the parent file).
4. If `expanded_filepath == target_filepath`, return (already showing the right file's issues).
5. Look up the IndexEntry for `target_filepath` from `self.entries`.
6. Call `load_expanded_issues(target_filepath, entry, self.filter, self.context)` and store the result in `self.expanded_issues`.
7. Set `expanded_filepath = target_filepath`.
8. Re-run `build_visible_rows()`.
9. Update `selected_index` to point to the same row in the new `visible_rows` (find by matching type + filepath/issue_id).
10. Re-render (which resizes the window and applies selection highlight).

### Navigate (`<C-n>` / `<C-p>` / `<Down>` / `<Up>`)

`move_selection(delta)`:
1. If `#visible_rows == 0`, return (no-op).
2. Adjust `selected_index` by `delta` (+1 for down, -1 for up).
3. Wrap around: if below 1, go to `#visible_rows`; if above `#visible_rows`, go to 1.
4. Call `update_expansion()`.
5. Call `apply_selection_highlight()`.

## Input Line Behavior

- The buffer remains modifiable at all times (the user types on the input line).
- On `TextChangedI` autocmd: extract the query text from the last line (strip the `> ` prefix), store in `self.query`, call `on_input_changed()`.
- `on_input_changed()`:
  1. Set `expanded_filepath = nil`, `expanded_issues = {}`.
  2. Re-run `build_display_entries()` with current filter and new query.
  3. Re-run `build_visible_rows()`.
  4. Reset `selected_index` to 1.
  5. Call `update_expansion()` to auto-expand the first file.
  6. Re-render the buffer (preserving the input line content).
  7. Apply selection highlight.

## Render

The `render()` method rebuilds the entire buffer:

1. Build header line: `"HuginnHome"` left-aligned, `"[Filter: LABEL]"` right-aligned.
2. Separator line.
3. Row lines from `visible_rows`, or `"(no files match)"` placeholder:
   - **File row**: `filepath .. "  (" .. count .. ")"`.
   - **Issue row**: `"  " .. description .. "  (" .. reference .. ")"` (parenthetical omitted when reference is nil).
4. Footer separator.
5. Help text line: `Enter open  q close  C-f filter  C-n/C-p/arrows navigate`.
6. Input line: `"> " .. self.query`.
7. Update `line_map` mapping entry line numbers to their corresponding `VisibleRow`.
8. Set buffer lines.
9. Resize the window height to fit `max(#visible_rows, 1) + 5`, capped at 50% editor height.
10. Place cursor on the input line at end of text.
11. Apply selection highlight.

## Public API

### home_window.open(opts)

Opens the floating window. `opts` contains:
- `entries`: `map<string, IndexEntry>` — all indexed files and their issues
- `context`: `CommandContext` — command context

If the window is already open and valid, focuses it instead of creating a duplicate.

### home_window.close()

Closes the floating window and cleans up state.

### home_window.is_open()

Returns `boolean` — whether the window is currently open and valid.

### home_window._close()

Close and reset (testing escape hatch).

### home_window._get_window()

Get the active Window instance (testing only).

## Autocmds

- **WinClosed**: Clean up state when the window is closed externally (e.g., `:q`).
- **VimResized**: Recalculate window dimensions and reposition.
- **CursorMoved / CursorMovedI**: Clamp cursor to input line.
- **TextChangedI**: Extract query from input line, re-filter, re-render.
