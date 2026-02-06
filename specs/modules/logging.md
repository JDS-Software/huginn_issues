# Logging

The logging module provides a dependency-injected logger instance that other modules receive via the [context](context.md) rather than requiring directly. All log output is held in an in-memory buffer for the session's lifetime; file persistence is optional and controlled by configuration.

## Log Levels

```lua
---@alias huginn.LogLevel "INFO" | "WARN" | "ERROR"
```

## Class Structure

### Logger

```lua
---@class huginn.Logger
{
  enabled = boolean,       -- whether file persistence is active
  filepath = string,       -- absolute path to log output file
  buffer = string[],       -- internal log line buffer (append-only)
  flushed_count = integer, -- number of lines already written to file
}
```

- `enabled` controls file persistence only — the in-memory buffer always accumulates regardless of this flag.
- `filepath` is the destination for `flush`. Typically absolutized by the context module after config is loaded.
- `buffer` is the authoritative log store for the session. The `log_viewer` component reads it directly via `get_buffer()`.
- `flushed_count` tracks incremental flush progress. Only lines after this index are written on the next flush, avoiding duplicate writes.

## Line Format

Each log line is formatted with a local timestamp:

```
[YYYY-MM-DD HH:MM:SS] LEVEL: message
```

For example: `[2026-01-09 14:32:56] WARN: Unknown config section: [widgets]`. The timestamp uses local time (via `os.date`), not UTC — log files are intended for human reading in the user's timezone.

## Functions

### M.new(enabled, filepath) -> Logger

Creates a new Logger instance. `enabled` defaults to `false` if falsy; `filepath` defaults to `".huginnlog"` if nil. If `enabled` is true, autocmds for automatic flushing are registered immediately (see [Automatic Flushing](#automatic-flushing)).

The logger is typically created early in plugin initialization with persistence disabled, then reconfigured after the configuration is loaded (see [context specification](context.md#singleton-lifecycle)).

### Logger:log(level, message)

Appends a formatted log line to the in-memory buffer. Silent — no user-visible output. This is the appropriate method for routine diagnostic information that the user has not asked to see.

### Logger:alert(level, message)

Appends a formatted log line to the in-memory buffer (via `log`) and additionally displays the message to the user via `nvim_echo`. The message is prefixed with `[Huginn] ` and highlighted based on level:

- **ERROR** — `ErrorMsg` highlight group
- **WARN** — `WarningMsg` highlight group
- **INFO** — `Normal` highlight group

Use `alert` for information the user needs to see immediately: errors that block an operation, warnings about configuration problems, or confirmations of user-initiated actions (e.g. "Created issue: 20260109_143256").

### Logger:flush()

Writes unflushed buffer lines to the log file. No-op if `enabled` is false or if all lines have already been flushed. Uses `vim.fn.writefile` in append mode (`"a"`) so that multiple flushes within a session accumulate in the same file. After a successful write, `flushed_count` advances to the current buffer length.

### Logger:configure(enabled, filepath?)

Reconfigures the logger with new settings. Updates `enabled` and, if `filepath` is non-nil, replaces the log file path. If enabling persistence, registers autocmds (see [Automatic Flushing](#automatic-flushing)). Buffer contents are preserved — all pre-existing log lines carry forward and will be flushed to the new path on the next flush.

### Logger:get_buffer() -> string[]

Returns a direct reference to the internal buffer array. The `log_viewer` component uses this to populate its display. Since the reference is live, the viewer can re-read it on refresh without requiring a new call.

## Automatic Flushing

When file persistence is enabled, the logger registers two autocmds under the `HuginnLogging` augroup (with `clear = true`):

- **BufWritePost** — flushes after any buffer write. This piggybacks on the user's natural save cadence to keep the log file reasonably current.
- **VimLeavePre** — flushes before Neovim exits, ensuring no buffered lines are lost.

The augroup is created with `clear = true`, so calling `_setup_autocmds` multiple times (e.g. via `configure`) replaces rather than duplicates the autocmds.
