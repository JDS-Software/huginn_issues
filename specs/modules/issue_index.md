# Huginn Index

The Huginn Index needs to track information about issues.

## Filepath Hashing

The caching schema starts by sha256 hashing (via `vim.fn.sha256`) the filepath (relative to the parent directory of the .huginn config file) of the source code file. This gives a 64 character string; we take the index.key_length configuration option and clamp it between 16 and 64 (inclusive). This section of the sha256 hash shall be referred to as the truncated_hash. Then, fan-out using the scheme described in [the issue spec](spec_issue.md). Since collisions are possible, the index files leverage the ability of the ini parser to have multiple sections.

The contents of this file will leverage the ini scheme described by the ini_parser in the following fashion:

### Index File Contents

```ini
[<relative filepath>]
{yyyyMMdd_kkmmss} = open # open issue
{yyyyMMdd_kkmmss} = closed # closed issue

[<relative filepath>]
{yyyyMMdd_kkmmss} = open #another file's issue
```

This allows quick parsing into structured data and allows the plugin to detect collisions.

### Index Directory Structure

The `.index/` directory lives inside `<config.plugin.issue_dir>/`. For the time-based issue directory structure, see [the issue specification](spec_issue.md#directory-structure).

The index file names are some part or whole of the full 64 character hash. The minimum length is 16 and the maximum length is 64. The actual length is determined by config.index.key_length unless that value is invalid. The file names should exactly match the truncated_hash.

```
<context.cwd>/<config.plugin.issue_dir>/  # see spec_context.md
 |
 +-- .index/                        # hidden directory - discourages use
      |
      +-- <truncated_hash[0:3]>/
      |    |
      |    +-- <truncated_hash>      # contains filepath & issue IDs
      |    |
      |    +-- <truncated_hash>
      |
      +-- <truncated_hash[0:3]>/
           |
           +-- <truncated_hash>
```

Where:
 - truncated_hash is the substring of the full sha256 hash, clamped to `config.index.key_length` characters (between 16 and 64 inclusive)

### Index Cache

The index cache maps from the index file name (the truncated hash) to a table of entries for that file: map<truncated_hash, map<filepath, IndexEntry>>.

## IndexEntry class

The IndexEntry class should be the (de)serialization vehicle for the index files. It has the following structure:
```lua
{
    filepath = <filepath>,
    dirty = false,
    issues = {
        <Huginn ID> = "open", -- open issue
        <Huginn ID> = "closed", -- closed issue
    },
}
```

Index files should be parsed into an IndexEntry instance using "M.parse(lines_iterator)", and IndexEntry shall have a "to_string" method to serialize to a string for persisting to disk. If an issue is removed (as opposed to closed), its entry should be removed.

Any operation that mutates the IndexEntry renders it dirty. This includes creating a new issue, closing an issue, removing an issue, re-opening a closed issue.

## Concerns

During plugin setup *and after configuration change*, we need to check the configuration against the files inside the index. If the filenames have a length that is different from config.index.key_length, we need to rename the files (since we're taking the first characters, the 3-character prefix should not change, meaning this change is in-place). This should be a 2 pass process, pass 1) compute and store new hashes; collisions detected here, pass 2) renaming from old hash to new hash. If a rename produces a new collision (two old files map to the same new truncated hash), the migration must still complete — merge the colliding files' sections into a single index file. The collision dialogue will be shown to the user next session.

If a collision is detected at any time (creating an issue in a file for the first time, during length migration), a dialogue should be shown to the user once per session telling them what happened, and asking them to modify the configuration file to increase the value of index.key_length. The HuginnConfig command makes it easy. However, the data can still be written by adding a new section for the new filepath.

## Cache Laziness

Issue files should be loaded when buffers are opened or when the plugin is doing a full index scan. In general, whenever an index file is read, its contents should be memoized for future use. Except for issue creation (which uses [write-through](#cache-write-through)), mutations mark the IndexEntry as dirty and are flushed lazily — on buffer write or Neovim exit, the cache should scan for dirty IndexEntries and persist them to disk.

There should be a public function "full_scan" that clears the cache and walks through the index directory and reads everything into memory.

The cache should map from the truncated hash to a table of IndexEntries, so a typical get should go in the following fashion.

```pseudocode.lua
function M.get(filepath)
    ctx = context.get()
    ...
    local full_hash = sha256(filepath)
    local hash = string.sub(full_hash, 0, ctx.config.index.key_length)
    local entries = cache[hash]
    if entries then
        local entry = entries[filepath]
        if entry then
            return entry
        end
        -- cache bucket exists but no entry for this filepath;
        -- fall through to disk load below
    end
    -- attempt to load index file from disk
    local loaded = load_from_disk(hash)
    if loaded then
        cache[hash] = loaded
        local entry = loaded[filepath]
        if entry then
            return entry
        end
    end
    return nil -- no entry exists in cache or on disk
end
```

## Cache Write-Through

Issue creation must be immediately persisted to disk to prevent data loss — a newly created issue that only exists in cache would be lost on unexpected exit. Status changes and removals are lower risk (the issue files themselves still exist on disk) and are handled by the lazy flush described in [Cache Laziness](#cache-laziness).

### Creation
Look up (or create) the IndexEntry for the source file, insert the new issue ID with status `"open"`, mark dirty, and immediately write the containing index file to disk. Clear the dirty flag after successful write.

### Status change
Update the issue's status in the IndexEntry (open to closed or vice versa) and mark dirty. Persisted during lazy flush.

### Removal
Remove the issue ID from the IndexEntry's issues table and mark dirty. Persisted during lazy flush.

