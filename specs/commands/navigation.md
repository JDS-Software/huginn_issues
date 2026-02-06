# HuginnNext / HuginnPrevious

Dependencies: `context`, `issue`, `issue_index`, `location`, `filepath`.

## Purpose

HuginnNext and HuginnPrevious navigate the cursor to the next or previous issue location in the current buffer. They allow the user to cycle through all annotated lines without manually searching for them. Both commands wrap around: after reaching the last issue location, HuginnNext jumps back to the first; after the first, HuginnPrevious jumps to the last.

## Command Registration

| Command | Range | Default keymap |
|---------|-------|----------------|
| `:HuginnNext` | false | `<leader>hn` |
| `:HuginnPrevious` | false | `<leader>hp` |

## Command Flow

Both commands share the same core logic, differing only in direction. The shared flow is:

1. Capture `CommandContext` via `context.from_command(opts)`.
2. Derive relative filepath from `cmd_ctx.window.filepath` and `cmd_ctx.cwd`.
3. Look up `issue_index.get(rel_filepath)` to obtain the IndexEntry.
4. If no IndexEntry exists (no issues for this file), notify the user and return.
5. Collect all open issue IDs from the IndexEntry (skip closed issues).
6. If no open issues exist, notify the user and return.
7. For each open issue, call `issue.read(id)` and resolve its location via `location.resolve(cmd_ctx.cwd, issue.location)`.
8. Collect all resolved line numbers (0-indexed `start_row` from each `node:range()` where `result == "found"`). Deduplicate across issues — multiple issues on the same line produce a single entry.
9. Include file-scoped issues (no references, or unresolvable references) at line 0.
10. If no lines were collected, notify the user and return.
11. Sort the collected lines in ascending order.
12. Determine the current cursor line (convert from 1-based to 0-based for comparison).
13. Find the target line based on direction (see Navigation Logic below).
14. Move the cursor to the target line, column 1 (first non-blank character via `vim.cmd("normal! ^")`), using 1-based line indexing for the Neovim API.

## Navigation Logic

### HuginnNext

Starting from the current cursor line (0-indexed), find the first entry in the sorted line list that is **strictly greater than** the cursor line. If no such entry exists (cursor is on or past the last issue line), wrap to the first entry in the list.

### HuginnPrevious

Starting from the current cursor line (0-indexed), find the last entry in the sorted line list that is **strictly less than** the cursor line. If no such entry exists (cursor is on or before the first issue line), wrap to the last entry in the list.

### Edge Cases

- **Single issue line**: Both commands always jump to that line, regardless of cursor position, unless the cursor is already on it — in which case the cursor stays (the single entry wraps to itself).
- **Cursor on an issue line**: The command does not stay on the current line. It moves to the next/previous issue line. If it is the only issue line, wrap-around returns to the same line (no-op visually).
