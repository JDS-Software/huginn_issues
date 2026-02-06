# HuginnHome

Dependencies: `context`, `issue`, `issue_index`, `home_window`.

## Purpose

HuginnHome displays a floating window listing all project files that have issues. It provides a project-wide overview with filter cycling, fuzzy search, and keyboard navigation to quickly jump to any file with tracked issues.

## Command Registration

- **Command**: `:HuginnHome`
- **Range**: false (no range support)
- **Default keymap**: `<leader>hh`

## Command Flow

1. Capture `CommandContext` via `context.from_command(opts)`. If it returns an error, return the error string.
2. Run `issue_index.full_scan()` to load all index data into memory. If it returns an error, return the error string.
3. Call `issue_index.all_entries()` to obtain a flat `map<filepath, IndexEntry>`.
4. If the map is empty (no files have issues), notify the user via `cmd_ctx.logger:alert("INFO", "No issues in project")` and return.
5. Open the home_window via `home_window.open(opts)` passing:
   - `entries`: the flat map of filepath -> IndexEntry
   - `context`: the CommandContext

## New Module Additions

### issue_index.all_entries()

Returns a flattened `map<filepath, IndexEntry>` from the module-local cache. Pure read, no mutations, returns a new table each call.

```lua
function M.all_entries()
    local result = {}
    for _, bucket in pairs(cache) do
        for fp, entry in pairs(bucket) do
            result[fp] = entry
        end
    end
    return result
end
```

This function should be placed after `M.full_scan()` in `issue_index.lua`.
