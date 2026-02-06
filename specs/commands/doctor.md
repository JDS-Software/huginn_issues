# HuginnDoctor

Dependencies: `context`, `doctor`.

## Purpose

HuginnDoctor runs an issue integrity scan and walks the user through interactive repairs. It is a maintenance command with no default keymap.

## Command Registration

- **Command**: `:HuginnDoctor`
- **Range**: false (no range support)
- **Default keymap**: none

## Command Flow

1. Capture `CommandContext` via `context.from_command(opts)`. If it returns an error, return the error string.
2. Call `doctor.scan(cmd_ctx.cwd, cmd_ctx.config)` to classify all indexed issues. If it returns an error, return the error string.
3. Count problems: `#missing_file + #broken_refs + #missing_index`.
4. If the count is zero, notify the user via `cmd_ctx.logger:alert("INFO", "All N issues healthy")` and return.
5. Notify the user of the problem count via `cmd_ctx.logger:alert("INFO", "Found N problem(s)")`.
6. Call `doctor.repair(cmd_ctx, scan_results)` to begin the interactive repair flow.
