# Location

Dependencies: `ini_parser`, `filepath`, `logging`. Accepts `CommandContext` (see `context.lua`) as a parameter via duck typing — no `require` dependency on the context module.

## Class Structure

***Location Class***
```lua
{
 filepath = string - path to source code file, relative to context.cwd
 reference = string[] - Array of "type|symbol" strings
}
```

This class must be (de)serializable using the ini_parser module.
```ini
[location] #location keyword
filepath = relative/path/to/file
reference[] = type|symbol
reference[] = type|symbol
```

Each reference is a `type|symbol` couplet where `type` is a tree-sitter node type (e.g., `function_declaration`, `method_definition`, `class_definition`) and `symbol` is the name of that construct. Types are stored as raw tree-sitter node type strings — they are language-specific and the module does not normalize or validate them across grammars. This is intentional: storing the exact node type allows `resolve` to query the tree directly by type and symbol without a translation layer.

**Named scopes**: The location module targets a specific set of tree-sitter constructs that define named scopes:
- **Function declarations/definitions** — nodes like `function_declaration`, `function_definition`
- **Method definitions** — nodes like `method_definition`, `function_method`
- **Class definitions** — nodes like `class_declaration`, `class_definition`
- **Variables assigned to anonymous functions** — nodes like `variable_declaration` or `assignment` where the value is a function expression. The symbol is the variable name, not the function (which is anonymous).

These categories are collectively referred to as "named scopes" throughout this spec. Constructs outside these categories (plain variable declarations, imports, type definitions, etc.) are not tracked. The node type examples above are illustrative — actual types vary by language grammar. The `|` delimiter is not escaped; symbols containing `|` are unsupported (no known language permits `|` in identifiers). If no references are present, the issue is scoped to the file as a whole.

## Responsibilities

The location module's job is to handle source code location data for the plugin. We need to reconcile location needs from 3 perspectives:
1) A command runs and it has context regarding the cursor's location. The module should be able to turn the context location into a Location instance.
2) A Location has been parsed from an issue and the caller wants the tree-sitter node(s) related to that location data
3) A caller has an array of tree-sitter nodes for a file and would like to create a Location instance

## Tree-sitter Availability

`from_context` and `resolve` require a tree-sitter parser for the file's language. If no parser is available, both return an error (`nil, error` for `from_context`; the caller receives an error from `resolve`). It is not the location module's job to install parsers or fall back to a degraded mode.

## Functions

### from_context(cmd_ctx) -> Location?, string?

Responsibility 1. Accepts a `CommandContext` (see [context specification](spec_context.md)). Uses `cmd_ctx.window` for cursor position, mode, and source filepath, `cmd_ctx.buffer` for tree-sitter queries, and `cmd_ctx.cwd` for relativizing the filepath. Returns `nil, error` if `cmd_ctx.window` is nil or if no tree-sitter parser is available for the buffer's filetype.

**Scope extraction rules:**

- **Normal mode**: Find the innermost named scope (see definition above) enclosing the cursor. That single scope becomes the sole reference. If the cursor is not enclosed by any named scope, the Location is file-scoped (empty references).
- **Visual mode**: Iterate line-by-line through the selection range (from `start.line` to `finish.line`). For each line, identify the innermost named scope enclosing that line, then deduplicate across all lines. If every line resolves to the same scope, that scope is the sole reference (same as normal mode). If lines resolve to different scopes, each unique scope becomes a separate reference. For example, a selection spanning methods A and B inside class C yields `{A, B}` — the enclosing class is never included because it is not the innermost scope at any line within A or B.
- **Nesting**: Only the innermost named scope is captured per cursor position. Enclosing parent scopes are not included.

### resolve(cwd, location) -> table\<string, {result, node}\>?, string?

Responsibility 2. Takes a deserialized Location and the context root path. Absolutizes `location.filepath` via `cwd`, then checks for an existing buffer for that path. If a buffer exists, uses its tree-sitter parser — buffer content is authoritative, even if the buffer has unsaved modifications. Otherwise reads the file from disk and uses `vim.treesitter.get_string_parser()`. Returns `nil, error` only for hard failures (no tree-sitter parser available, file not found). Otherwise always returns the full map — each reference carries its own resolution status. The caller decides how to handle partial matches. Each map entry is keyed by the `type|symbol` reference string with a value containing:
- `result`: `"found"` (exactly one match), `"not_found"` (symbol no longer exists or type mismatch), or `"ambiguous"` (multiple nodes match the type and symbol).
- `node`: the matched `TSNode` when `result` is `"found"`, `nil` otherwise.

For file-scoped Locations (no references), `resolve` returns an empty table `{}`.

### from_nodes(rel_filepath, source, nodes) -> Location?, string?

Responsibility 3. Builds a Location from a relative filepath and an array of `TSNode` objects. `source` is the buffer number (integer) or file content (string) that the nodes were parsed from — required by `vim.treesitter.get_node_text` to extract symbol names. For each node, the type is `node:type()` and the symbol is extracted from the node's `name` field (`node:field("name")`), reading the text of the resulting child node. For the "variable assigned to anonymous function" case, the symbol comes from the variable's name node, not the anonymous function. If a node has no `name` field, it is skipped. If the nodes array is empty or nil, returns a file-scoped Location (filepath only, no references).

### find_all_scopes(cwd, rel_filepath) -> userdata[]?, string?

Parse a source file and return all named scope nodes as an array of `TSNode` objects. Acquires a tree-sitter tree (preferring an open buffer, falling back to reading from disk) and walks it to collect every node that qualifies as a named scope. Returns `nil, error` if the file cannot be read or no tree-sitter parser is available.

### find_all_scope_refs(cwd, rel_filepath) -> string[]?, string?

Parse a source file and return all named scopes as deduplicated `"type|symbol"` reference strings. Internally calls `acquire_tree` and `collect_all_scopes`, then maps each scope node to a `make_ref(node:type(), get_symbol(node, source))` string. Duplicate references (same type and symbol) are collapsed. Returns `nil, error` if the file cannot be read or no tree-sitter parser is available.

### serialize(location) -> string

Produces an INI-formatted string suitable for embedding in an Issue.md Location block. Delegates to `ini_parser.serialize` internally.

### deserialize(content, logger?) -> Location?, string?

Parses an INI-formatted Location block string and returns a Location instance. Delegates to `ini_parser.parse` internally. Accepts an optional `logger` parameter (a logging module instance) for warning output.

**Error cases:**
- Missing `[location]` section or missing `filepath` key: return `nil, error`.
- Malformed `reference[]` values (no `|` delimiter): skip the malformed entry and, if a `logger` was provided, log a warning. Valid entries are still included.
