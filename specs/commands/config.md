# HuginnConfig

Dependencies: `context`, `filepath`.

## Purpose

HuginnConfig opens the `.huginn` configuration file in the current window for editing. Changes are picked up automatically via the config module's `BufWritePost` reload.

## Command Registration

- **Command**: `:HuginnConfig`
- **Range**: false
- **Default keymap**: none

## Command Flow

1. Retrieve the context singleton via `context.get()`. If unavailable, return an error.
2. Construct the absolute path by joining `ctx.cwd` with `".huginn"`.
3. Open the file via `:edit`.
