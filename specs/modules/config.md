# Huginn Configuration

Dependencies: `ini_parser`, `filepath`, `logging`. Manages the `.huginn` configuration file lifecycle — defaults, loading, merging, and live reload.

The `.huginn` file should be placed at the root of Huginn's context. Filepaths in the configuration are relative to this context root. Only one `.huginn` file should exist per project. The file uses the INI format described in the [INI parser specification](ini_parser.md).

## Defaults

Default values are defined as a map of `ConfigSection` entries keyed by header name, with a separate `section_order` array controlling iteration order:

```lua
---@class huginn.ConfigOption
{
  name = string,                              -- key name
  default = boolean|number|string,            -- native default value
  validate = fun(value: any, opts?: table): boolean, -- validator function
  opts? = table,                              -- duck-typed params for validate (e.g. { min, max })
}

---@class huginn.ConfigSection
{
  load_default = boolean,       -- whether this section is loaded at runtime
  options = ConfigOption[],     -- ordered list of option definitions
}
```

Defaults are materialized into an INI string via `materialize_defaults(false)`, parsed through `ini_parser.parse`, validated against each option's validator, and memoized. Each call to `get_defaults` returns a deep copy — callers can safely mutate the result without affecting the canonical defaults.

Sections with `load_default = false` are included in generated config files (as commented-out examples) but do not contribute to the runtime defaults table.

### Validation

Each `ConfigOption` carries a `validate` function that receives the parsed value and an optional `opts` table. Built-in validators:

- **is_boolean(value)** — checks `type(value) == "boolean"`
- **is_string(value, opts)** — checks `type(value) == "string"`; if `opts.pattern` is provided, the value must also match the Lua pattern
- **is_integer(value, opts)** — checks integer type; if `opts` is provided, enforces `opts.min` and/or `opts.max` bounds

Validation runs at two points:

1. **Startup** — parsed defaults are validated against their own validators. Failures indicate a programming error and emit a `vim.notify` warning.
2. **Load** — each user value is validated. Invalid values trigger a `logger:alert` warning and fall back to the default. Unknown keys within known sections are warned and discarded.

## Module State

```lua
M.active = table    -- merged configuration, accessible as config.active.section.key
M.huginn_path = string|nil  -- absolute path to the loaded .huginn file
```

`M.active` is the live configuration table shared across the plugin. The [context module](context.md) stores a reference to it — changes from `load` or `reload` are immediately visible to all holders.

## Functions

### load(huginn_path, logger?) -> table?, string?

Parses the `.huginn` file and merges user values onto a fresh copy of the defaults. User values take precedence — each valid user key overwrites the corresponding default. Unknown sections trigger a warning and are discarded. Unknown keys within known sections and values that fail validation also trigger warnings and are discarded (the default is kept). On success, populates `M.active` and `M.huginn_path`.

If `M.huginn_path` already matches the given path, returns the existing `M.active` without re-parsing.

### reload(logger?) -> table?, string?

Clears `M.huginn_path` and calls `load` with the previously stored path. Returns `nil, error` if no file was previously loaded. Used by the [context module's config reload](context.md#config-reload) on `BufWritePost`.

### generate_default_file() -> string

Produces the content for a new `.huginn` file. All sections are included with their default values commented out. Sections with `load_default = false` get an explanatory comment. Used by the `HuginnInit` command.

## Configuration Values

A table of configuration options may be found in the [Configuration Cheatsheet](../cheatsheet_config.md).
