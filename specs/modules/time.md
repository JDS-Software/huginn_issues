# Time

## ID Format

Huginn IDs follow the pattern `yyyyMMdd_HHmmss`, e.g. `20260109_143256`. The underscore separates the date component from the time component. IDs are always derived from UTC time — never local time. This ensures that IDs are globally ordered and deterministic regardless of the user's timezone.

The ID decomposes into a directory path for issue storage (see [issue specification](issue.md#time-directories)):

```
20260109_143256  →  2026/01/20260109_143256/Issue.md
```

## Class Structure

### IdTime

Parsed representation of a Huginn ID.

```lua
---@class huginn.IdTime
{
  year = integer,
  month = integer,   -- 1–12
  day = integer,     -- 1–31
  hour = integer,    -- 0–23
  minute = integer,  -- 0–59
  second = integer,  -- 0–59
}
```

### Timestamp

Parsed representation of an ISO 8601 timestamp string. Structurally identical to `IdTime` — they are separate types to clarify provenance, not to enforce different shapes.

```lua
---@class huginn.Timestamp
{
  year = integer,
  month = integer,   -- 1–12
  day = integer,     -- 1–31
  hour = integer,    -- 0–23
  minute = integer,  -- 0–59
  second = integer,  -- 0–59
}
```

## Functions

### generate_id() -> string

Generates a Huginn ID from the current UTC time via `os.date("!*t")`. Returns a string in `yyyyMMdd_HHmmss` format.

ID uniqueness relies on second precision. The [issue module](issue.md#id-collisions) is responsible for handling the collision case where two issues are created within the same second — the time module itself has no collision awareness.

### parse_id(id) -> IdTime?

Parses a Huginn ID string into an `IdTime` structure. Returns `nil` if `id` is not a string or does not match the `yyyyMMdd_HHmmss` pattern. This function performs format matching only — it does not validate value ranges. Use `is_valid_id` for full validation.

### is_valid_id(id) -> boolean

Validates both format and value ranges of a Huginn ID. Returns `false` if the string does not match `yyyyMMdd_HHmmss` or if any component falls outside its valid range:

- **month**: 1–12
- **day**: 1–31
- **hour**: 0–23
- **minute**: 0–59
- **second**: 0–59

Day validation is coarse — `is_valid_id` accepts day 31 for all months, including February. Calendar-accurate day validation is not performed.

### get_utc_timestamp() -> string

Returns the current UTC time as an ISO 8601 string in the format `"YYYY-MM-DD HH:MM:SS UTC"`, e.g. `"2026-01-09 14:32:56 UTC"`.

### parse_timestamp(timestamp) -> Timestamp?

Parses an ISO 8601 timestamp string (as produced by `get_utc_timestamp`) into a `Timestamp` structure. The trailing timezone label (e.g. `UTC`) is not captured — the caller is responsible for knowing the timezone semantics. Returns `nil` if `timestamp` is not a string or does not match the expected pattern.

### id_to_local_time(id) -> string?

Converts a Huginn ID to a human-readable local time string for display. The output format is `"YYYY-MM-DD HH:MM:SS TZ"`, e.g. `"2026-01-09 09:32:56 EST"`. Returns `nil` if the ID is invalid.

The conversion pipeline: parse the ID into an `IdTime`, convert to UTC epoch seconds, then format via `os.date` using the system's local timezone. The timezone abbreviation (e.g. `EST`, `CET`) is appended when available from the system; if the system returns an empty timezone string, the abbreviation is omitted.

## UTC Epoch Conversion

The module uses a private helper to convert time structures to UTC epoch seconds. Lua's `os.time` interprets its input as local time and has no UTC mode, so the conversion compensates by computing the local-to-UTC offset:

1. Pass the time structure to `os.time` (interpreted as local time).
2. Convert the result back to a UTC time table via `os.date("!*t", ...)`.
3. Pass that UTC table back through `os.time` to get the UTC interpretation.
4. The difference between step 1 and step 3 is the timezone offset.
5. Subtract the offset from the step 1 result to produce true UTC epoch seconds.

This approach is portable across platforms and does not depend on any Neovim APIs.
