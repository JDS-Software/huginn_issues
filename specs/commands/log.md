# HuginnLog

Dependencies: `log_viewer`.

## Purpose

HuginnLog opens the log viewer floating window, displaying the current session's log buffer.

## Command Registration

- **Command**: `:HuginnLog`
- **Range**: false
- **Default keymap**: none

## Command Flow

1. Call `log_viewer.open(logger)` with the session logger instance.
