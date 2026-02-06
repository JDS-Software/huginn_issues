# HuginnCreate

Dependencies: `context`, `issue`, `location`, `filepath`, `annotation`, `prompt`.

## Purpose

HuginnCreate creates a new issue linked to the current cursor position (or visual selection). It captures the source code location via tree-sitter, prompts for a description, writes the issue to disk, and refreshes annotations.

## Command Registration

- **Command**: `:HuginnCreate`
- **Range**: true (visual mode selection)
- **Default keymap**: `<leader>hc` (normal and visual mode)

## Command Flow

1. Capture `CommandContext` via `context.from_command(opts)`.
2. Extract location via `location.from_context(cmd_ctx)`. If tree-sitter is unavailable or extraction fails, log a warning and fall back to file-scoped — relativize `cmd_ctx.window.filepath` against `cmd_ctx.cwd` and use empty references.
3. Open the prompt component with the title "Issue Description".
4. If the user dismisses the prompt (callback receives `nil`), abort.
5. Call `issue.create(loc, description)`. An empty string is a valid description — the issue is created with no "Issue Description" block.
6. On failure, alert the user and return.
7. On success, alert with the new issue ID and call `annotation.refresh()`.
8. If `config.issue.open_after_create` is true, open the Issue.md file via `:edit`.
