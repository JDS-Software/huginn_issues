# Annotation

Dependencies: `context`, `issue_index`, `issue`, `location`, `filepath`. Read-only view layer that renders virtual text markers on buffer lines with associated issues.

## Display

Annotations use the blackbird unicode sequence followed by the open issue count:

```
🐦‍⬛(2) local function foo()
```

- **Open issues** — `🐦‍⬛(N)` where N is the count of open issues at that line.
- **Closed-only** — `🐦‍⬛[†]` on line 1 when the file has closed issues but no open ones. The dagger signals historical activity without visual noise on individual lines.
- **No issues** — annotations are cleared entirely.

## Virtual Text

Annotations are rendered using `nvim_buf_set_extmark` with `virt_text_pos = "eol"`. All extmarks live under a single namespace:

```lua
local ns = vim.api.nvim_create_namespace("huginn_annotation")
```

The `HuginnAnnotation` highlight group is configured from `config.annotation.background` and `config.annotation.foreground` (defaults: `"#ffffff"` / `"#000000"`).

## Functions

### setup()

Registers the namespace, sets the highlight group from config, creates autocmds, and registers a config change listener. Called once during plugin initialization.

**Autocmds** (under the `HuginnAnnotation` augroup):
- **BufEnter** — annotate the entered buffer.
- **BufWritePost** — re-annotate after save (picks up index changes from issue creation).

**Config change listener**: updates the highlight group colors and calls `refresh()`.

### annotate(bufnr)

Computes and displays annotations for a single buffer. No-op if the context is unavailable, `config.annotation.enabled` is false, or the buffer is invalid/unnamed.

1. Relativize the buffer path against `context.cwd`.
2. Look up the IndexEntry via `issue_index.get`.
3. If no entry exists, clear annotations and return.
4. Partition issue IDs into open and closed sets.
5. If no open and no closed issues, return.
6. If no open issues but closed issues exist, place the dagger indicator on line 0 and return.
7. For each open issue, read it and resolve its location:
   - **Found references** — increment the count at the resolved line (`start_row` from `node:range()`). An issue is counted once per line even if multiple references resolve to the same line.
   - **Unresolvable references** — fall back to line 0 (file-scoped).
   - **No references / no location** — line 0 (file-scoped).
8. Place one extmark per line with the aggregated count.

### clear(bufnr)

Clears all huginn extmarks from a buffer via `nvim_buf_clear_namespace`.

### refresh()

Re-annotates the current buffer. Called after issue creation, status toggle, deletion, and config changes.

## Testing

The module exposes `_reset()` which clears all extmarks across all buffers, nils the namespace, and clears the augroup. `_get_ns()` exposes the namespace handle for test assertions.
