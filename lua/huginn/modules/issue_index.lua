-- Copyright (c) 2026-present JDS Consulting, PLLC.
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is furnished
-- to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

-- issue_index.lua
-- Issue index: maps source filepaths to their issue IDs via SHA256 hash fanout


local context = require("huginn.modules.context")
local ini_parser = require("huginn.modules.ini_parser")
local filepath = require("huginn.modules.filepath")

local M = {}

local MIN_KEY_LENGTH = 16
local MAX_KEY_LENGTH = 64

---@class huginn.IndexEntry
---@field filepath string relative filepath (the INI section name)
---@field dirty boolean whether this entry has unsaved mutations
---@field issues table<string, string> map of issue ID -> "open"|"closed"
local IndexEntry = {}
IndexEntry.__index = IndexEntry

--- Create a new IndexEntry with an empty issues table
---@param fp string relative filepath
---@return huginn.IndexEntry
function IndexEntry.new(fp)
    return setmetatable({
        filepath = fp,
        dirty = false,
        issues = {},
    }, IndexEntry)
end

--- Insert or update an issue. Marks dirty.
---@param issue_id string
---@param status string "open"|"closed"
function IndexEntry:set(issue_id, status)
    self.issues[issue_id] = status
    self.dirty = true
end

--- Remove an issue ID from the table. Marks dirty if the issue existed.
---@param issue_id string
function IndexEntry:remove(issue_id)
    if self.issues[issue_id] then
        self.issues[issue_id] = nil
        self.dirty = true
    end
end

--- Check if an issue ID exists
---@param issue_id string
---@return boolean
function IndexEntry:has(issue_id)
    return self.issues[issue_id] ~= nil
end

--- Check if the issues table is empty
---@return boolean
function IndexEntry:is_empty()
    return next(self.issues) == nil
end

--- Parse raw index file content into IndexEntries
---@param content string raw file content
---@return table<string, huginn.IndexEntry> entries map of filepath -> IndexEntry
function M.parse_index_file(content)
    local parsed = ini_parser.parse(content)
    local entries = {}

    for section_name, kv in pairs(parsed) do
        local entry = IndexEntry.new(section_name)
        for issue_id, status in pairs(kv) do
            if status == "open" or status == "closed" then
                entry.issues[issue_id] = status
            end
        end
        entry.dirty = false
        entries[section_name] = entry
    end

    return entries
end

--- Serialize a map of IndexEntries to INI string
---@param entries table<string, huginn.IndexEntry>
---@return string
function M.serialize_entries(entries)
    local data = {}
    for fp, entry in pairs(entries) do
        if not entry:is_empty() then
            data[fp] = {}
            for id, status in pairs(entry.issues) do
                data[fp][id] = status
            end
        end
    end
    return ini_parser.serialize(data)
end

--- Clamp key_length to [16, 64]
---@param key_length number
---@return number
local function clamp_key_length(key_length)
    if key_length < MIN_KEY_LENGTH then return MIN_KEY_LENGTH end
    if key_length > MAX_KEY_LENGTH then return MAX_KEY_LENGTH end
    return math.floor(key_length)
end

--- Compute truncated SHA256 hash of a relative filepath
---@param relative_filepath string
---@param key_length number
---@return string truncated_hash
local function compute_hash(relative_filepath, key_length)
    local full_hash = vim.fn.sha256(relative_filepath)
    return string.sub(full_hash, 1, clamp_key_length(key_length))
end

--- Compute filesystem path for an index file
---@param issue_dir string absolute path to issue directory
---@param truncated_hash string
---@return string path absolute path to the index file
local function hash_to_path(issue_dir, truncated_hash)
    local prefix = string.sub(truncated_hash, 1, 3)
    return filepath.join(issue_dir, ".index", prefix, truncated_hash)
end

--- Ensure parent directory exists
---@param path string file path
---@return boolean ok
---@return string|nil error
local function ensure_parent_dir(path)
    local parent = filepath.dirname(path)
    local ok, err = pcall(vim.fn.mkdir, parent, "p")
    if not ok then return false, "Failed to create directory: " .. err end
    return true, nil
end

--- Read and parse an index file from an absolute path
---@param file_path string absolute path to the index file
---@return table<string, huginn.IndexEntry>|nil entries
local function read_index_file(file_path)
    local ok, lines = pcall(vim.fn.readfile, file_path)
    if not ok then return nil end
    local content = table.concat(lines, "\n")
    local entries = M.parse_index_file(content)
    if entries and next(entries) then
        return entries
    end
    return nil
end

--- Iterate files inside a single fanout prefix directory
---@param prefix_path string absolute path to the 3-char prefix directory
---@param callback fun(file_name: string, file_path: string)
local function each_index_file_in(prefix_path, callback)
    local file_handle = vim.uv.fs_scandir(prefix_path)
    if not file_handle then return end

    while true do
        local file_name, file_type = vim.uv.fs_scandir_next(file_handle)
        if not file_name then break end
        if file_type == "file" then
            callback(file_name, filepath.join(prefix_path, file_name))
        end
    end
end

--- Walk every index file under the .index/ directory
---@param index_dir string absolute path to the .index directory
---@param callback fun(file_name: string, file_path: string)
local function walk_index_dir(index_dir, callback)
    local handle = vim.uv.fs_scandir(index_dir)
    if not handle then return end

    while true do
        local prefix_name, prefix_type = vim.uv.fs_scandir_next(handle)
        if not prefix_name then break end
        if prefix_type == "directory" then
            each_index_file_in(filepath.join(index_dir, prefix_name), callback)
        end
    end
end

--- Count entries in a table
---@param tbl table
---@return number
local function tbl_count(tbl)
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    return n
end

--- Extract the clamped key_length from a context
---@param ctx huginn.Context
---@return number
local function ctx_key_length(ctx)
    return clamp_key_length(ctx.config.index.key_length)
end

--- Derive the absolute issue directory path from a context
---@param ctx huginn.Context
---@return string
local function ctx_issue_dir(ctx)
    return filepath.join(ctx.cwd, ctx.config.plugin.issue_dir)
end

--- Derive the absolute .index/ directory path from a context
---@param ctx huginn.Context
---@return string
local function ctx_index_dir(ctx)
    return filepath.join(ctx_issue_dir(ctx), ".index")
end

--- map<truncated_hash, map<filepath, IndexEntry>>
local cache = {}

--- Whether the collision alert has been shown this session
local collision_alerted = false

--- Whether the .index/.gitignore has been ensured this session
local gitignore_ensured = false

--- Ensure a .gitignore containing "*" exists in the .index/ directory
---@param issue_dir string absolute path to issue directory
local function ensure_index_gitignore(issue_dir)
    if gitignore_ensured then return end
    local gitignore_path = filepath.join(issue_dir, ".index", ".gitignore")
    if not filepath.exists(gitignore_path) then
        pcall(vim.fn.mkdir, filepath.join(issue_dir, ".index"), "p")
        pcall(vim.fn.writefile, { "*" }, gitignore_path)
    end
    gitignore_ensured = true
end

--- Load an index file from disk
---@param ctx huginn.Context
---@param truncated_hash string
---@return table<string, huginn.IndexEntry>|nil entries
local function load_from_disk(ctx, truncated_hash)
    local path = hash_to_path(ctx_issue_dir(ctx), truncated_hash)
    if not filepath.exists(path) then
        return nil
    end
    return read_index_file(path)
end

--- Write a cache bucket to disk. Clears dirty flags on success.
--- Deletes the index file if all entries are empty.
---@param ctx huginn.Context
---@param truncated_hash string
---@return boolean ok
---@return string|nil error
local function write_to_disk(ctx, truncated_hash)
    local entries = cache[truncated_hash]
    local path = hash_to_path(ctx_issue_dir(ctx), truncated_hash)

    local should_delete = not entries
    if entries then
        local any_non_empty = false
        for _, entry in pairs(entries) do
            if not entry:is_empty() then
                any_non_empty = true
                break
            end
        end
        should_delete = not any_non_empty
    end

    if should_delete then
        if filepath.exists(path) then
            vim.fn.delete(path)
        end
        return true, nil
    end

    local content = M.serialize_entries(entries)
    local ok_mkdir, mkdir_err = ensure_parent_dir(path)
    if not ok_mkdir then return false, mkdir_err end

    ensure_index_gitignore(ctx_issue_dir(ctx))

    local ok_write, write_err = pcall(vim.fn.writefile, vim.split(content, "\n"), path)
    if not ok_write then return false, "Failed to write index file: " .. write_err end

    for _, entry in pairs(entries) do
        entry.dirty = false
    end
    return true, nil
end

--- Alert user about hash collision (once per session)
---@param ctx huginn.Context
local function alert_collision(ctx)
    if collision_alerted then return end
    collision_alerted = true
    if ctx.logger then
        ctx.logger:alert("WARN",
            "Hash collision detected in issue index. " ..
            "Consider increasing index.key_length in your .huginn config.")
    end
end

--- Get the IndexEntry for a source filepath
---@param rel_filepath string relative path to source file
---@return huginn.IndexEntry|nil entry
---@return string|nil error
function M.get(rel_filepath)
    local ctx = context.get()
    if not ctx then return nil, "Plugin context not initialized" end

    local truncated_hash = compute_hash(rel_filepath, ctx_key_length(ctx))

    local bucket = cache[truncated_hash]
    if bucket then
        return bucket[rel_filepath], nil
    end

    local loaded = load_from_disk(ctx, truncated_hash)
    if loaded then
        cache[truncated_hash] = loaded
        return loaded[rel_filepath], nil
    end

    return nil, nil
end

--- Create a new issue in the index (write-through: immediately persisted)
---@param rel_filepath string relative path to source file
---@param issue_id string huginn issue ID
---@return huginn.IndexEntry|nil entry
---@return string|nil error
function M.create(rel_filepath, issue_id)
    local ctx = context.get()
    if not ctx then return nil, "Plugin context not initialized" end

    local truncated_hash = compute_hash(rel_filepath, ctx_key_length(ctx))

    if not cache[truncated_hash] then
        cache[truncated_hash] = load_from_disk(ctx, truncated_hash) or {}
    end

    local entry = cache[truncated_hash][rel_filepath]
    if not entry then
        entry = IndexEntry.new(rel_filepath)
        cache[truncated_hash][rel_filepath] = entry
    end

    entry:set(issue_id, "open")

    if tbl_count(cache[truncated_hash]) > 1 then
        alert_collision(ctx)
    end

    local ok, write_err = write_to_disk(ctx, truncated_hash)
    if not ok then return nil, write_err end
    return entry, nil
end

--- Close an issue (lazy flush)
---@param rel_filepath string relative path to source file
---@param issue_id string huginn issue ID
---@return boolean success
---@return string|nil error
function M.close(rel_filepath, issue_id)
    local entry, err = M.get(rel_filepath)
    if err then return false, err end
    if not entry then return false, "No index entry for filepath" end
    if not entry:has(issue_id) then return false, "Issue ID not found in index" end

    entry:set(issue_id, "closed")
    return true, nil
end

--- Reopen a closed issue (lazy flush)
---@param rel_filepath string relative path to source file
---@param issue_id string huginn issue ID
---@return boolean success
---@return string|nil error
function M.reopen(rel_filepath, issue_id)
    local entry, err = M.get(rel_filepath)
    if err then return false, err end
    if not entry then return false, "No index entry for filepath" end
    if not entry:has(issue_id) then return false, "Issue ID not found in index" end

    entry:set(issue_id, "open")
    return true, nil
end

--- Remove an issue from the index (lazy flush)
---@param rel_filepath string relative path to source file
---@param issue_id string huginn issue ID
---@return boolean success
---@return string|nil error
function M.remove(rel_filepath, issue_id)
    local entry, err = M.get(rel_filepath)
    if err then return false, err end
    if not entry then return false, "No index entry for filepath" end

    entry:remove(issue_id)
    return true, nil
end

--- Flush all dirty entries to disk
function M.flush()
    local ctx = context.get()
    if not ctx then return end

    for hash, entries in pairs(cache) do
        local any_dirty = false
        for _, entry in pairs(entries) do
            if entry.dirty then
                any_dirty = true
                break
            end
        end
        if any_dirty then
            write_to_disk(ctx, hash)
        end
    end
end

--- Clear the cache and walk the entire .index/ directory into memory
---@return number|nil count number of IndexEntries loaded
---@return string|nil error
function M.full_scan()
    local ctx = context.get()
    if not ctx then return nil, "Plugin context not initialized" end

    local index_dir = ctx_index_dir(ctx)
    cache = {}

    if not filepath.exists(index_dir) then
        return 0, nil
    end

    local count = 0
    walk_index_dir(index_dir, function(file_name, file_path)
        local entries = read_index_file(file_path)
        if entries then
            cache[file_name] = entries
            count = count + tbl_count(entries)
        end
    end)

    return count, nil
end

--- Return a flat map of all cached entries
---@return table<string, huginn.IndexEntry> entries map of filepath -> IndexEntry
function M.all_entries()
    local result = {}
    for _, bucket in pairs(cache) do
        for fp, entry in pairs(bucket) do
            result[fp] = entry
        end
    end
    return result
end

--- Register autocmds for lazy flushing and config-change listener
function M.setup()
    local group = vim.api.nvim_create_augroup("HuginnIndex", { clear = true })

    vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        callback = function() M.flush() end,
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function() M.flush() end,
    })

    context.on_config_change(function(new_config)
        local new_kl = clamp_key_length(new_config.index.key_length)
        if needs_migration(new_kl) then
            M.migrate_key_length(new_kl)
        end
    end)
end

--- Check if any existing index file has a name length that differs from target
---@param target_key_length number desired key length
---@return boolean
local function needs_migration(target_key_length)
    local ctx = context.get()
    if not ctx then return false end

    local index_dir = ctx_index_dir(ctx)
    if not filepath.exists(index_dir) then return false end

    local dominated = false
    walk_index_dir(index_dir, function(file_name, _)
        if #file_name ~= target_key_length then
            dominated = true
        end
    end)
    return dominated
end

--- Build migration plan by scanning existing index files
---@param index_dir string absolute path to .index directory
---@param new_key_length number clamped target key length
---@return table[] migration_map list of {old_path, new_hash, filepath, entry}
---@return table<string, number[]> new_hash_groups new_hash -> indices into migration_map
local function build_migration_plan(index_dir, new_key_length)
    local migration_map = {}
    local new_hash_groups = {}

    walk_index_dir(index_dir, function(_, file_path)
        local entries = read_index_file(file_path)
        if not entries then return end

        for fp, entry in pairs(entries) do
            local new_hash = compute_hash(fp, new_key_length)
            local idx = #migration_map + 1
            migration_map[idx] = {
                old_path = file_path,
                new_hash = new_hash,
                filepath = fp,
                entry = entry,
            }
            if not new_hash_groups[new_hash] then
                new_hash_groups[new_hash] = {}
            end
            table.insert(new_hash_groups[new_hash], idx)
        end
    end)

    return migration_map, new_hash_groups
end

--- Execute the migration: merge entries by new hash, write new files, delete old ones
---@param issue_dir string absolute path to issue directory
---@param migration_map table[] from build_migration_plan
---@param new_hash_groups table<string, number[]> from build_migration_plan
---@return boolean had_collision
---@return string|nil error
local function execute_migration(issue_dir, migration_map, new_hash_groups)
    local old_files = {}
    for _, item in ipairs(migration_map) do
        old_files[item.old_path] = true
    end

    local had_collision = false

    for new_hash, indices in pairs(new_hash_groups) do
        local merged = {}
        for _, idx in ipairs(indices) do
            local item = migration_map[idx]
            merged[item.filepath] = item.entry
            item.entry.dirty = false
        end

        if tbl_count(merged) > 1 then
            had_collision = true
        end

        local new_path = hash_to_path(issue_dir, new_hash)
        local ok_mkdir, mkdir_err = ensure_parent_dir(new_path)
        if not ok_mkdir then return false, mkdir_err end

        local content = M.serialize_entries(merged)
        local ok_write, write_err = pcall(vim.fn.writefile, vim.split(content, "\n"), new_path)
        if not ok_write then return false, "Failed to write migrated index file: " .. write_err end

        old_files[new_path] = nil
    end

    for old_path, _ in pairs(old_files) do
        if filepath.exists(old_path) then
            vim.fn.delete(old_path)
        end
    end

    return had_collision, nil
end

--- Remove empty fanout directories inside the .index/ directory
---@param index_dir string absolute path to .index directory
local function cleanup_empty_fanout_dirs(index_dir)
    local handle = vim.uv.fs_scandir(index_dir)
    if not handle then return end

    while true do
        local name, dir_type = vim.uv.fs_scandir_next(handle)
        if not name then break end
        if dir_type == "directory" then
            local dir_path = filepath.join(index_dir, name)
            local sub_handle = vim.uv.fs_scandir(dir_path)
            if sub_handle and not vim.uv.fs_scandir_next(sub_handle) then
                vim.fn.delete(dir_path, "d")
            end
        end
    end
end

--- Migrate index files when key_length changes
---@param new_key_length number new key_length (will be clamped)
function M.migrate_key_length(new_key_length)
    local ctx = context.get()
    if not ctx then return end

    new_key_length = clamp_key_length(new_key_length)
    local issue_dir = ctx_issue_dir(ctx)
    local index_dir = ctx_index_dir(ctx)

    if not filepath.exists(index_dir) then return end

    local migration_map, new_hash_groups = build_migration_plan(index_dir, new_key_length)
    if #migration_map == 0 then return end

    local had_collision, mig_err = execute_migration(issue_dir, migration_map, new_hash_groups)
    if mig_err then
        if ctx.logger then
            ctx.logger:log("ERROR", "Index migration failed: " .. mig_err)
        end
        return
    end
    cleanup_empty_fanout_dirs(index_dir)

    if had_collision then
        alert_collision(ctx)
    end

    cache = {}
    M.full_scan()
end

--- Check cache integrity: verify each indexed issue_id maps to an existing issue on disk.
--- Evicts stale entries and rewrites affected index files.
--- Operates directly on disk so it works without full plugin context.
---@param issue_dir string absolute path to issue directory
---@param issue_exists_fn fun(issue_dir: string, issue_id: string): boolean
---@return table results {checked: number, evicted: number, evicted_ids: string[]}
function M.check_integrity(issue_dir, issue_exists_fn)
    local index_dir = filepath.join(issue_dir, ".index")
    local checked = 0
    local evicted = 0
    local evicted_ids = {}

    if not filepath.exists(index_dir) then
        return { checked = checked, evicted = evicted, evicted_ids = evicted_ids }
    end

    walk_index_dir(index_dir, function(_, file_path)
        local entries = read_index_file(file_path)
        if not entries then return end

        local dirty = false
        for _, entry in pairs(entries) do
            local to_remove = {}
            for issue_id, _ in pairs(entry.issues) do
                checked = checked + 1
                if not issue_exists_fn(issue_dir, issue_id) then
                    table.insert(to_remove, issue_id)
                end
            end
            for _, issue_id in ipairs(to_remove) do
                entry:remove(issue_id)
                evicted = evicted + 1
                table.insert(evicted_ids, issue_id)
                dirty = true
            end
        end

        if dirty then
            local any_non_empty = false
            for _, entry in pairs(entries) do
                if not entry:is_empty() then
                    any_non_empty = true
                    break
                end
            end
            if any_non_empty then
                local content = M.serialize_entries(entries)
                pcall(vim.fn.writefile, vim.split(content, "\n"), file_path)
            else
                vim.fn.delete(file_path)
            end
        end
    end)

    cache = {}

    return { checked = checked, evicted = evicted, evicted_ids = evicted_ids }
end

--- Reset cache and session flags (testing only)
function M._clear()
    cache = {}
    collision_alerted = false
    gitignore_ensured = false
end

--- Exposed for testing
M._IndexEntry = IndexEntry
M._compute_hash = compute_hash
M._clamp_key_length = clamp_key_length
M._hash_to_path = hash_to_path

return M
