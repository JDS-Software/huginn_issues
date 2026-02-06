# Doctor

Dependencies: `issue_index`, `issue`, `location`, `filepath`, `annotation`.

## Purpose

The doctor module scans all indexed issues, classifies their health, and provides interactive repair. It detects three categories of problems: source files that no longer exist, tree-sitter references that no longer resolve, and index entries that are out of sync with the issue's stored location.

## Class Structure

***DoctorResult***
```lua
{
    issue_id = string,        -- Huginn ID
    issue = HuginnIssue,      -- the deserialized issue
    rel_filepath = string,    -- relative filepath from the index entry
    category = string,        -- "ok"|"missing_file"|"broken_refs"|"missing_index"
    broken_refs = string[]?,  -- which refs failed (only for "broken_refs" category)
}
```

***ScanResults***
```lua
{
    ok = DoctorResult[],           -- healthy issues
    missing_file = DoctorResult[], -- source file no longer exists
    broken_refs = DoctorResult[],  -- file exists but ref(s) not found
    missing_index = DoctorResult[],-- issue location filepath differs from index key
    total = number,                -- total issues scanned
    errors = string[],             -- issue IDs that could not be read
}
```

## Functions

### scan(cwd, config) -> ScanResults?, string?

Scans all indexed issues and classifies each into one of four categories.

**Algorithm:**

1. Call `issue_index.full_scan()` to populate the cache.
2. Call `issue_index.all_entries()` to get all `(rel_filepath, IndexEntry)` pairs.
3. For each `(issue_id, status)` in each entry's issues table:
   - `issue.read(issue_id)` — on failure, record in `errors`, skip.
   - **File check**: `filepath.exists(filepath.join(cwd, rel_filepath))`. If missing, classify as `missing_file`.
   - **Reference check**: If the issue has references, call `location.resolve(cwd, issue.location)`. If resolve returns a results table and any ref has `result == "not_found"`, classify as `broken_refs` with those refs collected. If resolve returns `nil + error` (no parser available, etc.), treat as `ok` — the module cannot verify, so it does not flag.
   - **Index cross-check**: If `issue.location.filepath ~= rel_filepath`, verify `issue_index.get(issue.location.filepath)` contains this issue_id. If missing, classify as `missing_index`.
   - Otherwise classify as `ok`.

**Error handling:**
- Returns `nil, error` if `cwd` or `config` is nil.
- Returns `nil, error` if `issue_index.full_scan()` fails.

### repair(cmd_ctx, scan_results) -> nil

Runs interactive repair in four sequential phases. Phases 2 and 3 are asynchronous (callback-driven via `vim.ui.select`).

**Phase 1 — Auto-repair missing index** (synchronous):
For each `missing_index` item, call `issue_index.create(issue.location.filepath, issue_id)`. If the issue is CLOSED, also call `issue_index.close()`. Then `issue_index.flush()`. Log the count.

**Phase 2 — Relocate orphaned files** (async, one at a time):
Collect all project files via `vim.fn.glob`, excluding directories and the issue directory. For each `missing_file` item, present `vim.ui.select` with the file list (prepended with a "-- Skip --" sentinel). On selection, call `issue.relocate(issue_id, chosen_filepath)`. After a successful relocation, immediately test the issue's references against the new file via `location.resolve`. If any references come back `not_found`, feed them into the broken-refs repair flow inline before advancing to the next missing-file item. On skip or cancel, advance to the next item.

**Phase 3 — Fix broken references** (async, one ref at a time):
For each `broken_refs` item, for each broken ref: call `location.find_all_scope_refs(cwd, rel_filepath)` to enumerate available scopes, then present `vim.ui.select`. On selection, call `issue.remove_reference(issue_id, old_ref)` + `issue.add_reference(issue_id, new_ref)`. On skip or cancel, advance to the next ref. Issues that already had their refs repaired inline during Phase 2 are not revisited.

**Phase 4 — Cleanup**:
Call `annotation.refresh()` and log a summary via `cmd_ctx.logger:alert`.

## Health Check Integration

The `:checkhealth huginn` health module (in `health.lua`) calls `doctor.scan()` to report an "Issue integrity" section. It lists counts for each problem category with advice to run `:HuginnDoctor`. If all issues are healthy, it reports `vim.health.ok`. The doctor module is lazy-required to avoid circular dependencies.
