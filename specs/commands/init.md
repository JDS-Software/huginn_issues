# HuginnInit

Dependencies: `context`, `config`, `filepath`, `confirm`.

## Purpose

HuginnInit creates a `.huginn` configuration file in the current working directory with default values, reinitializes the plugin, and opens the file for editing.

## Command Registration

- **Command**: `:HuginnInit`
- **Range**: false
- **Default keymap**: none

## Command Flow

1. Check for an existing context via `context.get()`.
2. **If a context exists** — a `.huginn` file is already loaded. Show a caution-level confirmation ("A .huginn configuration already exists. Replace it?"). If cancelled, abort.
3. **If no context exists** — derive the target path from `vim.fn.getcwd()` joined with `".huginn"`.
4. Generate file content via `config.generate_default_file()`.
5. Write to disk via `vim.fn.writefile`. On failure, alert and return.
6. Reset the context singleton and clear `config.huginn_path`.
7. Reinitialize via `context.init()` and `context.setup()`. If initialization fails, alert with a warning but continue.
8. Open the new `.huginn` file via `:edit`.
