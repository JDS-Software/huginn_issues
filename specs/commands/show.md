# HuginnShow

Dependencies: `context`, `issue`, `issue_index`, `location`, `annotation`, `show_window`.

## Purpose

HuginnShow displays a floating window listing all issues associated with the current buffer's source file. It provides a compact overview with filter cycling and inline actions (toggle status, delete).

## Command Registration

- **Command**: `:HuginnShow`
- **Range**: false (no range support)
- **Default keymap**: `<leader>hs`

## Command Flow

1. Capture `CommandContext` via `context.from_command(opts)`.
2. Derive relative filepath from `cmd_ctx.window.filepath` and `cmd_ctx.cwd`.
3. Resolve cursor location via `location.from_context(cmd_ctx)` to determine the cursor's scope references and the header context string. If tree-sitter is unavailable, fall back to file-scoped (show filepath only, no function name).
4. Look up `issue_index.get(rel_filepath)` to obtain the IndexEntry.
5. If no IndexEntry exists (no issues for this file), notify the user and return.
6. Read each issue via `issue.read(id)` for all issue IDs in the IndexEntry.
7. **Context-aware filtering**: only include issues that are relevant to the cursor position:
   - File-scoped issues (no references) are always included.
   - Scoped issues are included only if any of their references overlap with the cursor context's references.
8. If no relevant issues remain after filtering, notify the user ("No issues at this location") and return.
9. Open the show_window via `show_window.open(opts)` passing:
   - `issues`: the filtered list of relevant HuginnIssue objects
   - `header_context`: filepath and optional function name from step 3
   - `source_filepath`: relative filepath (for refresh/annotation operations)
   - `source_bufnr`: buffer number from cmd_ctx (for annotation refresh)
   - `config`: active config reference

## Issue Scope Display

Each issue's scope is derived from its Location:
- **File-scoped** (no references): display as `file`
- **Location-scoped** (has references): display as the symbol from the first reference, e.g., `M.setup`.

## Description Truncation

The "Issue Description" block content is truncated for compact display:
1. Find the index of the first period (`.`) character.
2. Find the index of the first newline (`\n`) character.
3. Take the minimum of: first period index, first newline index, `config.show.description_length`.
4. Substring to that length. If truncated by the length cap, append `...`.
5. If the "Issue Description" block is missing or empty, display `(no description)`.

## New Module Additions

### issue.delete(issue_id, callback)

Permanently removes an issue from disk and all related data structures. Owns the confirmation dialog — shows a danger-level confirmation before proceeding.

**Signature**: `issue.delete(issue_id, callback)` where `callback(deleted: boolean)` is called with `true` if deleted, `false` if cancelled or failed.

1. Read the issue via `issue.read(issue_id)` to obtain the Location filepath.
2. Show a danger-level confirmation dialog via `confirm.show()`.
3. If confirmed:
   a. Compute the issue directory path via `issue.issue_path(issue_id)` and derive its parent directory.
   b. Remove the `Issue.md` file from disk via `vim.fn.delete()`.
   c. Remove the issue directory via `vim.fn.delete(dir, "d")`. If the directory contains user-added files, warn and leave it (only delete if empty after Issue.md removal).
   d. Remove the issue from the index via `issue_index.remove(source_filepath, issue_id)`.
   e. Evict the issue from the issue module's internal cache.
   f. Call `callback(true)`.
4. If cancelled or on failure, call `callback(false)`.

### Config: [show] section

New configuration section with defaults:

```ini
[show]
description_length = 80
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| description_length | integer | 80 | Maximum character length for issue descriptions in the show window |
