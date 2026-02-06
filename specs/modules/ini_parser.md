# INI Parser

Dependencies: `filepath`. Shared parser and serializer for the INI format used across the plugin — `.huginn` config files, Location blocks in Issue.md, and index files.

## Format

Section headers: `[Header]`. Lines before any section header are dropped.

Comments: lines beginning with `#` as the first non-whitespace character are discarded.

Keys may not contain spaces. Values containing spaces must be wrapped in double-quotes. Unquoted values capture only the first word — everything after it (or after the closing quote) is discarded, which allows inline comments without a special comment character.

```
[example]
 key = value #This can be whatever you like
#key2 = "value with space" ;asm-style comments!
 key3 = "another value with space " You don't actually need a comment character

# Returned: { example: { key: "value", key3: "another value with space " } }
```

Leading and trailing whitespace around keys and values is trimmed. Whitespace inside quotes is preserved:

```
[example]
       key =    value
    key2 = " value"
key3 =          "value "

# Returned: { example: { key: "value", key2: " value", key3: "value " } }
```

### Type Coercion

Coercion is unconditional and applies after quote extraction. Quoting does not prevent it.

- `true` / `false` (case-sensitive) → boolean
- `([0-9]+)` or `([0-9]+.[0-9]+)` → number
- Everything else → string

### Duplicate Keys and Sections

Duplicate keys: last value wins. Keys ending with `[]` are aggregating — each occurrence appends to an array. The `[]` suffix is preserved in the key name.

```
[location]
filepath = relative/path/to/file
reference[] = function_declaration|foo
reference[] = method_definition|bar

# Returned: { location: { filepath: "...", ["reference[]"]: { "...|foo", "...|bar" } } }
```

Duplicate section headers reuse the same table — keys from both occurrences merge. This is how the [index module](issue_index.md) stores multiple filepaths in a single index file.

## Data Model

Both `parse` and `serialize` operate on:

```lua
table<string, table<string, any>>
```

Outer table keyed by section name, inner table by key name. Values are strings, numbers, booleans, or arrays (aggregating keys).

## Functions

### parse(content) -> table

Parses a raw INI string into the data model.

### serialize(data, section_order?) -> string

Converts the data model to an INI string. Returns `""` if `data` is nil or empty.

Sections listed in `section_order` are emitted first in that order; remaining sections are appended alphabetically. Keys within each section are sorted alphabetically. Sections are separated by blank lines. Output ends with a trailing newline.

Value formatting: booleans emit `true`/`false`, numbers emit `tostring`, strings are quoted if empty or containing spaces. Aggregating keys emit one `key = value` line per element.

### parse_file(path) -> table?, string?

Normalizes `path`, checks existence, reads with `vim.fn.readfile`, and delegates to `parse`. Returns `nil, error` if the path is nil/empty or the file does not exist.

## Round-Trip Limitations

`parse(serialize(data))` reproduces the input table with these exceptions:

- **Boolean/number coercion is lossy** — string `"true"` serializes bare, re-parses as boolean. Same for `"false"` and numeric strings.
- **Embedded double quotes** — the serializer does not escape `"` inside string values.
- **Pre-section lines** — dropped by `parse`, unrepresentable in the data model.
