# Huginn Context

Dependencies: `config`, `filepath`. The context module is the plugin's singleton state container. It separates durable state (persists for the plugin's lifetime) from ephemeral state (scoped to a single command execution). Other modules accept context fields via duck typing — they do not `require` the context module directly.

## Class Structure

### Position

```lua
---@class huginn.Position
{
  line = integer,  -- 1-based line number
  col = integer,   -- 1-based column number
}
```

### WindowState

Snapshot of the editor window at the moment a command is invoked. Captured once and not updated during command execution.

```lua
---@class huginn.WindowState
{
  filepath = string,          -- absolute path to the source file (buffer name)
  mode = string,              -- vim mode at invocation time ("n", "v", "V", "\22", etc.)
  start = huginn.Position,     -- cursor position (normal) or selection start (visual)
  finish = huginn.Position|nil -- selection end in visual mode, nil in normal mode
}
```

- **Normal mode**: `start` holds the cursor position, `finish` is nil.
- **Visual mode**: `start` and `finish` define the selection range. `start` is always the earlier position regardless of selection direction.

### Context (durable)

The singleton. Created once during plugin initialization and shared across all command invocations within a session.

```lua
---@class huginn.Context
{
  cwd = string,    -- absolute path to the context root (directory containing .huginn)
  config = table,  -- active configuration (see spec_config.md)
  logger = Logger, -- plugin logger instance (see plan_logging_module.md)
}
```

- `cwd` is the single source of truth for relativizing all filepaths in the plugin.
- `config` is a live reference — it is replaced in-place on config reload, so holders of the Context see the updated values.
- `logger` is configured during initialization with settings from the loaded config.

### CommandContext (ephemeral)

Created per command invocation by flattening the durable Context fields and adding buffer-specific state.

```lua
---@class huginn.CommandContext
{
  cwd = string,                  -- copied from Context.cwd
  config = table,                -- copied from Context.config
  logger = Logger,               -- copied from Context.logger
  buffer = integer,              -- neovim buffer number the command was executed from
  window = huginn.WindowState|nil -- editor window state at invocation, nil if unavailable
}
```

CommandContext deliberately copies references from Context rather than holding a reference to Context itself. This keeps downstream modules decoupled from the singleton — they accept individual fields via duck typing.

## Singleton Lifecycle

The context module maintains a single `Context` instance. The lifecycle proceeds as follows:

1. **Discovery**: Starting from a given path (or `vim.fn.getcwd()`), walk up the directory tree via `filepath.find_huginn_file()` to locate the `.huginn` config file.
2. **Configuration**: Load and merge config via `config.load()`. See [config spec](spec_config.md).
3. **Logger configuration**: After config is loaded, reconfigure the logger with `logging.enabled` and the absolutized `logging.filepath`.
4. **Instantiation**: Store the singleton. Subsequent calls to `get()` return this instance.

If discovery or configuration fails, no singleton is created and the plugin stays dormant.

## Config Reload

The context module registers a `BufWritePost` autocmd (under the `HuginnConfig` augroup) that watches for writes to the `.huginn` config file. On save:

1. The buffer's path is normalized and compared against the known `.huginn` path.
2. If matched, `config.reload()` is called to re-parse the file.
3. On success, the singleton's `config` field is replaced with the new config table.
4. All registered config-change listeners are notified in registration order.
5. On failure, a warning is sent via `logger:alert` and the existing config is preserved.

This allows users to modify settings mid-session without restarting Neovim. Other modules register listeners via `on_config_change(fn)` to react to configuration updates (e.g., the index module may need to handle key_length changes).

## Testing

The module exposes `_reset()` which clears the singleton instance and all registered listeners. This must be called between tests to prevent state leakage.
