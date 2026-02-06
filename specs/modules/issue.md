# Issue Specification

## Issue.md Structure

Issue.md files are structured as follows (concepts are wrapped in {} brackets):

```Markdown
# {Issue ID}

## Version
{Format Version}

## Status
{Status Value}

## {Block Label}
{Block Content}

## {Block Label}
Blocks can have arbitrary labels.

They can also have arbitrary text data within.

## {Block Label}
{Block Content}

```

### Issue ID
A human-readable timestamp with second precision: yyyyMMdd_HHmmss.
This ID represents the time that the issue was created.

### Block Label
Unique key for the section. Huginn will internally relate {Block Label} -> {Block Content}.

Reserved Block Labels:
 - Version
 - Status
 - Location
 - Issue Description
 - Issue Resolution


### Block Content
Arbitrary user data. The only constraint is that it may not contain H1 or H2 markdown headers (lines starting with `# ` or `## `), as these are reserved for Issue.md structure.
Sub-headers (`###` and below) are permitted. Otherwise, it may be treated like ordinary Markdown and contain arbitrary text.

Reserved blocks may define a structured format (e.g., INI) instead of free-form markdown. When a block has a structured format, Huginn will parse it accordingly rather than treating it as plain text.

## Huginn Issue Directory

The issue directory for Huginn is the central repository for tracking issues. It has 2 primary logical components: time directories and the index directory.

### Time Directories

Issues are stored in time-based directories derived from their ID (`yyyyMMdd_HHmmss`). The ID decomposes into a `YYYY/MM/<ID>/` filepath, where each issue directory contains an `Issue.md` file with the issue context.

### Index Directory

The index maps source files to their related issues and is stored under the `.index/` subdirectory of the issue directory. The relative filepath of a source file is hashed using SHA256, truncated to the `truncated_hash` (see [index specification](spec_index.md)), and stored using a 3-character fanout scheme. Each index file contains the IDs of issues related to that source file.

### Directory Structure

For the index directory structure, see [the index specification](spec_index.md#index-directory-structure).

```
<context.cwd>/<config.plugin.issue_dir>/  # see spec_context.md
 |
 +-- .index/                          # see spec_index.md
 |
 +-- YYYY/
 |    |
 |    +-- MM/
 |         |
 |         +-- <ID>/
 |         |    |
 |         |    +-- Issue.md
 |         |    |
 |         |    +-- arbitrary_user_data.md
 |         |
 |         +-- <ID>/
 |              |
 |              +-- Issue.md
 |
 +-- YYYY/
      |
      +-- MM/
           |
           +-- <ID>/
                |
                +-- Issue.md
```

Where:
- `<ID>` is the full issue ID in `yyyyMMdd_HHmmss` format
- Issue directories are regular directories. Huginn only reads `Issue.md`, but additional files of any type may be stored alongside it by users or external tools.

## Reserved Blocks

### Version

The Issue.md file format version number. Plain-text single value.
```Markdown
## Version
1
```

### Status

The issue's current state. Plain-text single value, either OPEN or CLOSED. Newly created issues default to OPEN.
```Markdown
## Status
OPEN
```

### Location

An ini-formatted block that contains the following information:
```ini
## Location
[location]
filepath = relative/path/to/file
reference[] = type|symbol
```

For more information see the [location module](spec_location.md)

### Issue Description

User-supplied description of the issue. Captured via prompt during the HuginnCreate command.

### Issue Resolution

User-supplied description of how the issue was ultimately resolved. Captured via prompt during the HuginnResolve command.


## HuginnIssue class

### Fields
id: string - The Huginn ID
version: number - Issue.md file format version; parsed from the Version block
status: string - "OPEN" or "CLOSED"; parsed from the Status block
location: Location - information about related source code; parsed from the Location block on deserialization and materialized back on serialization
blocks: map<string, string> - maps section_header -> section_content; contains all blocks except Version, Status, and Location, which are stored in their typed fields
mtime: number - last_modified time of the Issue.md file in seconds since epoch (from `vim.uv.fs_stat().mtime.sec`); used for detecting out-of-band changes

## Module responsibilities

Dependencies: context, issue_index, ini_parser, filepath, time.

The issue module is responsible for the lifecycle of Issue.md files. It must be able to materialize correct filepaths to issue files based on Huginn ID, it must be able to round-trip (de)serialize Issues, and it must be able to create new issues and update the index.

### Status transitions

- **close(issue_id)** — Sets the issue's status to CLOSED.
- **reopen(issue_id)** — Sets the issue's status to OPEN.

### Deletion

- **delete(issue_id, callback)** — Permanently removes an issue from disk and all related data structures. Shows a danger-level confirmation dialog before proceeding. On confirmation:
  1. Deletes the `Issue.md` file from disk.
  2. Removes the issue directory if it is empty. If user-added files remain, the directory is left in place with a warning.
  3. Removes the issue from the index (if the issue has a location).
  4. Evicts the issue from the in-memory cache.
  5. Calls `callback(true)`.
- If the user cancels the confirmation or any step fails, calls `callback(false)` and aborts without partial cleanup.

### Migration

The module must provide separate operations for relocating and reassigning issues:

- **relocate(issue_id, new_filepath)** — Updates the Location filepath and reindexes (removes the old hash entry, adds a new one for the new filepath). Used when a source file is moved or renamed.
- **add_reference(issue_id, reference)** — Adds a `type|symbol` reference to the issue's Location.
- **remove_reference(issue_id, reference)** — Removes a `type|symbol` reference from the issue's Location. If no references remain, the issue becomes file-scoped.

### Display

- **get_ui_description(cmd_ctx, issue)** — Returns a truncated description string suitable for UI display. Truncates at the first period, first newline, or `config.show.description_length` (default 80), whichever is shortest. Appends `...` if truncated by the length cap. Returns `(no description)` if the Issue Description block is empty or missing.

### ID collisions

Issue IDs have second precision. If a new issue's generated ID already exists on disk, sleep for 1 second and regenerate. Abort with an error after 3 failed attempts.

### Error recovery

When deserializing a malformed Issue.md:
- **Missing H1**: Regenerate the issue ID from the directory name (the containing directory is the ID).
- **Duplicate H2 labels**: Warn the user via the logging module and use last-in wins — the later block overwrites the earlier one.
- **Unparseable Location block**: Warn the user via the logging module and fall back to file-scoped (filepath only, empty references).

### Caching

The module must also maintain a cache that maps the Huginn Id to the relevant issue object. The HuginnIssue class holds an mtime for the file that it was deserialized from. On any access, the module must compare the cached mtime against the file's current mtime — if they differ, the cache entry is stale and fresh data must be loaded. This mtime check is the authoritative staleness mechanism and handles all modification sources (external editors, git operations, etc.). Autocmds (e.g., BufWritePost) may be used as an optimization to eagerly invalidate cache entries, but they are not required for correctness since the mtime check already covers those cases.

