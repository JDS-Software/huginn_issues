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

-- issue.lua
-- Issue lifecycle: create, read, write, serialize, deserialize, status transitions, migration


local context = require("huginn.modules.context")
local issue_index = require("huginn.modules.issue_index")
local filepath = require("huginn.modules.filepath")
local time = require("huginn.modules.time")
local location = require("huginn.modules.location")
local confirm = require("huginn.components.confirm")

local M = {}

local CURRENT_VERSION = 1
local MAX_ID_BACKTRACK = 60

-- Reserved block labels stored as typed fields on HuginnIssue
local RESERVED_TYPED = {
    Version = true,
    Status = true,
    Location = true,
}

-- Preferred serialization order for blocks after the typed reserved fields
local BLOCK_ORDER = {
    "Issue Description",
    "Issue Resolution",
}

---@class huginn.HuginnIssue
---@field id string Huginn ID (yyyyMMdd_HHmmss)
---@field version number Issue.md format version
---@field status string "OPEN" or "CLOSED"
---@field location huginn.Location? source code location
---@field blocks table<string, string> non-reserved block label -> content
---@field mtime number last-modified time (seconds since epoch)

--- Cache: issue ID -> HuginnIssue
local cache = {}

--- Get logger from context if available
---@return huginn.Logger?
local function get_logger()
    local ctx = context.get()
    return ctx and ctx.logger or nil
end

--- Strip leading and trailing blank lines from a block content array
---@param lines string[] array of lines
---@return string trimmed content joined with newlines
local function trim_block_content(lines)
    local start_idx = 1
    while start_idx <= #lines and lines[start_idx]:match("^%s*$") do
        start_idx = start_idx + 1
    end

    local end_idx = #lines
    while end_idx >= start_idx and lines[end_idx]:match("^%s*$") do
        end_idx = end_idx - 1
    end

    if start_idx > end_idx then
        return ""
    end

    local result = {}
    for i = start_idx, end_idx do
        table.insert(result, lines[i])
    end
    return table.concat(result, "\n")
end

--- Compute the absolute path to an Issue.md file from its ID
---@param id string Huginn ID (yyyyMMdd_HHmmss)
---@return string? path absolute path to Issue.md
---@return string? error
function M.issue_path(id)
    local ctx = context.get()
    if not ctx then return nil, "Plugin context not initialized" end

    local parsed = time.parse_id(id)
    if not parsed then return nil, "Invalid issue ID: " .. tostring(id) end

    local year = string.format("%04d", parsed.year)
    local month = string.format("%02d", parsed.month)
    local issue_dir = filepath.join(ctx.cwd, ctx.config.plugin.issue_dir)
    return filepath.join(issue_dir, year, month, id, "Issue.md"), nil
end

--- Serialize a HuginnIssue to Issue.md markdown string
---@param issue huginn.HuginnIssue
---@return string content markdown content
function M.serialize(issue)
    local parts = {}

    -- H1: Issue ID
    table.insert(parts, "# " .. issue.id)
    table.insert(parts, "")

    -- Version block
    table.insert(parts, "## Version")
    table.insert(parts, tostring(issue.version))

    -- Status block
    table.insert(parts, "")
    table.insert(parts, "## Status")
    table.insert(parts, issue.status)

    -- Location block
    if issue.location then
        table.insert(parts, "")
        table.insert(parts, "## Location")
        local loc_str = location.serialize(issue.location)
        -- Remove trailing newline from ini_parser output
        if loc_str:sub(-1) == "\n" then
            loc_str = loc_str:sub(1, -2)
        end
        table.insert(parts, loc_str)
    end

    -- Ordered blocks (Issue Description, Issue Resolution)
    local seen = {}
    for _, label in ipairs(BLOCK_ORDER) do
        if issue.blocks[label] then
            table.insert(parts, "")
            table.insert(parts, "## " .. label)
            table.insert(parts, issue.blocks[label])
            seen[label] = true
        end
    end

    -- Remaining custom blocks (alphabetical)
    local custom = {}
    for label, _ in pairs(issue.blocks) do
        if not seen[label] then
            table.insert(custom, label)
        end
    end
    table.sort(custom)
    for _, label in ipairs(custom) do
        table.insert(parts, "")
        table.insert(parts, "## " .. label)
        table.insert(parts, issue.blocks[label])
    end

    return table.concat(parts, "\n") .. "\n"
end

--- Deserialize Issue.md markdown content into a HuginnIssue
---@param content string markdown content
---@param dir_name string? directory name for H1 recovery
---@return huginn.HuginnIssue? issue
---@return string? error
function M.deserialize(content, dir_name)
    local logger = get_logger()
    local lines = vim.split(content, "\n")

    -- Find H1 for issue ID
    local id = nil
    local body_start = 1
    for i, line in ipairs(lines) do
        local h1 = line:match("^# (.+)")
        if h1 then
            id = vim.trim(h1)
            body_start = i + 1
            break
        end
    end

    -- Error recovery: missing H1
    if not id or id == "" then
        if dir_name and time.is_valid_id(dir_name) then
            id = dir_name
            if logger then
                logger:log("WARN", "Missing H1 in Issue.md, using directory name: " .. dir_name)
            end
        else
            return nil, "Missing issue ID (no H1 header)"
        end
    end

    -- Parse H2 blocks
    local raw_blocks = {}
    local current_label = nil
    local current_lines = {}

    local function save_block()
        if current_label then
            local block_content = trim_block_content(current_lines)
            if raw_blocks[current_label] then
                if logger then
                    logger:log("WARN",
                        "Duplicate H2 label '" .. current_label .. "' in issue " .. id .. ", using last occurrence")
                end
            end
            raw_blocks[current_label] = block_content
        end
    end

    for i = body_start, #lines do
        local h2 = lines[i]:match("^## (.+)")
        if h2 then
            save_block()
            current_label = vim.trim(h2)
            current_lines = {}
        elseif current_label then
            table.insert(current_lines, lines[i])
        end
    end
    save_block()

    -- Extract typed fields
    local version = CURRENT_VERSION
    if raw_blocks.Version then
        local v = tonumber(vim.trim(raw_blocks.Version))
        if v then version = v end
    end

    local status = "OPEN"
    if raw_blocks.Status then
        local s = vim.trim(raw_blocks.Status)
        if s == "OPEN" or s == "CLOSED" then
            status = s
        end
    end

    local loc = nil
    if raw_blocks.Location then
        local parsed_loc, loc_err = location.deserialize(raw_blocks.Location, logger)
        if parsed_loc then
            loc = parsed_loc
        else
            if logger then
                logger:log("WARN", "Unparseable Location in issue " .. id .. ": " .. (loc_err or "unknown"))
            end
        end
    end

    -- Build blocks map (exclude typed reserved blocks)
    local blocks = {}
    for label, block_content in pairs(raw_blocks) do
        if not RESERVED_TYPED[label] then
            blocks[label] = block_content
        end
    end

    return {
        id = id,
        version = version,
        status = status,
        location = loc,
        blocks = blocks,
        mtime = 0,
    }, nil
end

--- Write an issue to disk and update the cache
---@param issue huginn.HuginnIssue
---@return boolean success
---@return string? error
function M.write(issue)
    local path, err = M.issue_path(issue.id)
    if not path then return false, err end

    local dir = filepath.dirname(path)
    local ok_mkdir, mkdir_err = pcall(vim.fn.mkdir, dir, "p")
    if not ok_mkdir then return false, "Failed to create directory: " .. mkdir_err end

    local content = M.serialize(issue)
    local ok_write, write_err = pcall(vim.fn.writefile, vim.split(content, "\n"), path)
    if not ok_write then return false, "Failed to write issue file: " .. write_err end

    local stat = vim.uv.fs_stat(path)
    if stat then
        issue.mtime = stat.mtime.sec
    end

    cache[issue.id] = issue
    return true, nil
end

--- Read an issue by ID, using cache with mtime validation
---@param issue_id string Huginn ID
---@return huginn.HuginnIssue? issue
---@return string? error
function M.read(issue_id)
    local path, err = M.issue_path(issue_id)
    if not path then return nil, err end

    -- Check cache with mtime validation
    local cached = cache[issue_id]
    if cached then
        local stat = vim.uv.fs_stat(path)
        if stat and stat.mtime.sec == cached.mtime then
            return cached, nil
        end
    end

    -- Read from disk
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok then
        return nil, "Issue file not found: " .. path
    end
    local content = table.concat(lines, "\n")
    local dir_name = filepath.basename(filepath.dirname(path))

    local issue, parse_err = M.deserialize(content, dir_name)
    if not issue then return nil, parse_err end

    local stat = vim.uv.fs_stat(path)
    if stat then
        issue.mtime = stat.mtime.sec
    end

    cache[issue.id] = issue
    return issue, nil
end

--- Create a new issue
---@param loc huginn.Location location object (filepath used for indexing)
---@param description string issue description text
---@return huginn.HuginnIssue? issue
---@return string? error
function M.create(loc, description)
    local ctx = context.get()
    if not ctx then return nil, "Plugin context not initialized" end

    -- Generate ID with backward-scanning collision resolution
    local id = nil
    for offset = 0, MAX_ID_BACKTRACK - 1 do
        local candidate = time.generate_id_with_offset(offset)
        local candidate_path, path_err = M.issue_path(candidate)
        if not candidate_path then return nil, path_err end

        local candidate_dir = filepath.dirname(candidate_path)
        if not filepath.exists(candidate_dir) then
            id = candidate
            break
        end
    end

    if not id then
        return nil, "Failed to generate unique issue ID within " .. MAX_ID_BACKTRACK .. "-second backtrack window"
    end

    -- Build issue object
    local issue = {
        id = id,
        version = CURRENT_VERSION,
        status = "OPEN",
        location = loc,
        blocks = {},
        mtime = 0,
    }

    if description and description ~= "" then
        issue.blocks["Issue Description"] = description
    end

    -- Write to disk
    local ok, write_err = M.write(issue)
    if not ok then return nil, write_err end

    -- Update index
    local _, idx_err = issue_index.create(loc.filepath, id)
    if idx_err then
        return nil, "Failed to update index: " .. idx_err
    end

    return issue, nil
end

--- Resolve an issue: add resolution description, set status to CLOSED
---@param issue_id string Huginn ID
---@param description string resolution description text
---@return huginn.HuginnIssue? issue
---@return string? error
function M.resolve(issue_id, description)
    local issue, err = M.read(issue_id)
    if not issue then return nil, err end

    if issue.status ~= "OPEN" then
        return nil, "Cannot resolve issue " .. issue_id .. ": status is " .. issue.status .. ", expected OPEN"
    end

    local timestamp = time.get_utc_timestamp()
    issue.blocks["Issue Resolution"] = timestamp .. "\n" .. (description or "")
    issue.status = "CLOSED"

    local ok, write_err = M.write(issue)
    if not ok then return nil, write_err end

    if issue.location then
        issue_index.close(issue.location.filepath, issue_id)
    end

    return issue, nil
end

--- Reopen a closed issue (set status to OPEN)
--- If an "Issue Resolution" block exists, renames it to "Resolution Attempt N"
--- where N is the next 0-indexed sequence number.
---@param issue_id string Huginn ID
---@return huginn.HuginnIssue? issue
---@return string? error
function M.reopen(issue_id)
    local issue, err = M.read(issue_id)
    if not issue then return nil, err end

    if issue.status ~= "CLOSED" then
        return nil, "Cannot reopen issue " .. issue_id .. ": status is " .. issue.status .. ", expected CLOSED"
    end

    -- Rename "Issue Resolution" to "Resolution Attempt N" if present
    if issue.blocks["Issue Resolution"] then
        local next_n = 0
        for label, _ in pairs(issue.blocks) do
            local n = label:match("^Resolution Attempt (%d+)$")
            if n then
                local num = tonumber(n)
                if num >= next_n then
                    next_n = num + 1
                end
            end
        end

        issue.blocks["Resolution Attempt " .. next_n] = issue.blocks["Issue Resolution"]
        issue.blocks["Issue Resolution"] = nil
    end

    issue.status = "OPEN"

    local ok, write_err = M.write(issue)
    if not ok then return nil, write_err end

    -- Update index if location is available
    if issue.location then
        issue_index.reopen(issue.location.filepath, issue_id)
    end

    return issue, nil
end

--- Delete an issue permanently from disk and all related data structures.
--- Shows a danger-level confirmation dialog before proceeding.
---@param issue_id string Huginn ID
---@param callback fun(deleted: boolean) called with true if deleted, false if cancelled or failed
function M.delete(issue_id, callback)
    local logger = get_logger()

    local iss, read_err = M.read(issue_id)
    if not iss then
        if logger then
            logger:alert("ERROR", "Failed to read issue for deletion: " .. (read_err or "unknown"))
        end
        callback(false)
        return
    end

    confirm.show({
        message = "Delete issue " .. issue_id .. "?",
        level = "danger",
    }, function(confirmed)
        if not confirmed then
            callback(false)
            return
        end

        local path, path_err = M.issue_path(issue_id)
        if not path then
            if logger then
                logger:alert("ERROR", "Failed to resolve issue path: " .. (path_err or "unknown"))
            end
            callback(false)
            return
        end

        local dir = filepath.dirname(path)

        -- Remove Issue.md from disk
        if vim.fn.delete(path) ~= 0 then
            if logger then
                logger:alert("ERROR", "Failed to delete file: " .. path)
            end
            callback(false)
            return
        end

        -- Remove issue directory if empty; warn and leave if user-added files remain
        if vim.fn.delete(dir, "d") ~= 0 then
            if logger then
                logger:log("WARN", "Issue directory not empty after deletion, leaving: " .. dir)
            end
        end

        -- Remove from index
        if iss.location then
            issue_index.remove(iss.location.filepath, issue_id)
        end

        -- Evict from cache
        cache[issue_id] = nil

        callback(true)
    end)
end

--- Relocate an issue to a new source filepath
---@param issue_id string Huginn ID
---@param new_filepath string new relative filepath
---@return huginn.HuginnIssue? issue
---@return string? error
function M.relocate(issue_id, new_filepath)
    local issue, err = M.read(issue_id)
    if not issue then return nil, err end

    -- Remove old index entry
    if issue.location then
        issue_index.remove(issue.location.filepath, issue_id)
    end

    -- Update location
    if not issue.location then
        issue.location = { filepath = new_filepath, reference = {} }
    else
        issue.location.filepath = new_filepath
    end

    -- Write updated issue
    local ok, write_err = M.write(issue)
    if not ok then return nil, write_err end

    -- Add new index entry
    issue_index.create(new_filepath, issue_id)
    if issue.status == "CLOSED" then
        issue_index.close(new_filepath, issue_id)
    end

    -- Flush to ensure old removal is persisted
    issue_index.flush()

    return issue, nil
end

--- Add a reference to an issue's location
---@param issue_id string Huginn ID
---@param reference string "type|symbol" reference string
---@return huginn.HuginnIssue? issue
---@return string? error
function M.add_reference(issue_id, reference)
    local issue, err = M.read(issue_id)
    if not issue then return nil, err end

    if not issue.location then
        return nil, "Issue has no location"
    end

    -- Check for duplicates
    for _, ref in ipairs(issue.location.reference) do
        if ref == reference then
            return issue, nil
        end
    end

    table.insert(issue.location.reference, reference)

    local ok, write_err = M.write(issue)
    if not ok then return nil, write_err end

    return issue, nil
end

--- Remove a reference from an issue's location
---@param issue_id string Huginn ID
---@param reference string "type|symbol" reference string
---@return huginn.HuginnIssue? issue
---@return string? error
function M.remove_reference(issue_id, reference)
    local issue, err = M.read(issue_id)
    if not issue then return nil, err end

    if not issue.location then
        return nil, "Issue has no location"
    end

    local new_refs = {}
    local found = false
    for _, ref in ipairs(issue.location.reference) do
        if ref == reference then
            found = true
        else
            table.insert(new_refs, ref)
        end
    end

    if not found then
        return nil, "Reference not found: " .. reference
    end

    issue.location.reference = new_refs

    local ok, write_err = M.write(issue)
    if not ok then return nil, write_err end

    return issue, nil
end

--- Get a truncated description suitable for UI display
---@param cmd_ctx huginn.CommandContext
---@param issue huginn.HuginnIssue
---@return string
function M.get_ui_description(cmd_ctx, issue)
    local desc = issue.blocks and issue.blocks["Issue Description"]
    if not desc or desc == "" then
        return "(no description)"
    end

    local max_length = 80
    if cmd_ctx.config and cmd_ctx.config.show and cmd_ctx.config.show.description_length then
        max_length = tonumber(cmd_ctx.config.show.description_length) or 80
    end

    local dot_pos = desc:find("%.", 1, false)
    local nl_pos = desc:find("\n", 1, true)

    local cut = max_length
    if dot_pos and dot_pos < cut then cut = dot_pos end
    if nl_pos and nl_pos - 1 < cut then cut = nl_pos - 1 end

    if cut < #desc then
        local result = desc:sub(1, cut)
        if cut == max_length then result = result .. "..." end
        return result
    end
    return desc
end

--- Reset cache (testing only)
function M._reset()
    cache = {}
end

return M
