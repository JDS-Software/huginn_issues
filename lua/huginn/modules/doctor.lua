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

-- doctor.lua
-- Issue integrity scanner and interactive repair

local issue_index = require("huginn.modules.issue_index")
local issue = require("huginn.modules.issue")
local location = require("huginn.modules.location")
local filepath = require("huginn.modules.filepath")
local annotation = require("huginn.modules.annotation")

local M = {}

---@class huginn.DoctorResult
---@field issue_id string
---@field issue huginn.HuginnIssue
---@field rel_filepath string relative filepath from the index
---@field category string "ok"|"missing_file"|"broken_refs"|"missing_index"
---@field broken_refs string[]|nil which refs failed (only for broken_refs category)

---@class huginn.ScanResults
---@field ok huginn.DoctorResult[]
---@field missing_file huginn.DoctorResult[]
---@field broken_refs huginn.DoctorResult[]
---@field missing_index huginn.DoctorResult[]
---@field total number
---@field errors string[]

--- Scan all indexed issues and classify their health status.
---@param cwd string absolute path to context root
---@param config table active configuration
---@return huginn.ScanResults|nil results
---@return string|nil error
function M.scan(cwd, config)
    if not cwd or not config then
        return nil, "Plugin context not initialized"
    end

    local _, scan_err = issue_index.full_scan()
    if scan_err then
        return nil, scan_err
    end

    local results = {
        ok = {},
        missing_file = {},
        broken_refs = {},
        missing_index = {},
        total = 0,
        errors = {},
    }

    local entries = issue_index.all_entries()

    for rel_filepath, entry in pairs(entries) do
        for issue_id, _ in pairs(entry.issues) do
            results.total = results.total + 1

            local iss, read_err = issue.read(issue_id)
            if not iss then
                table.insert(results.errors, issue_id .. ": " .. (read_err or "unknown"))
                goto continue
            end

            local result = {
                issue_id = issue_id,
                issue = iss,
                rel_filepath = rel_filepath,
                category = "ok",
            }

            -- File check
            local abs_path = filepath.join(cwd, rel_filepath)
            if not filepath.exists(abs_path) then
                result.category = "missing_file"
                table.insert(results.missing_file, result)
                goto continue
            end

            -- Reference check
            if iss.location and #iss.location.reference > 0 then
                local resolve_results, resolve_err = location.resolve(cwd, iss.location)
                if resolve_results then
                    local broken = {}
                    for ref, res in pairs(resolve_results) do
                        if res.result == "not_found" then
                            table.insert(broken, ref)
                        end
                    end
                    if #broken > 0 then
                        result.category = "broken_refs"
                        result.broken_refs = broken
                        table.insert(results.broken_refs, result)
                        goto continue
                    end
                end
                -- If resolve returns nil+error (no parser, etc.), treat as ok
                if resolve_err then
                    -- Can't verify, don't flag
                end
            end

            -- Index cross-check
            if iss.location and iss.location.filepath ~= rel_filepath then
                local cross_entry = issue_index.get(iss.location.filepath)
                if not cross_entry or not cross_entry:has(issue_id) then
                    result.category = "missing_index"
                    table.insert(results.missing_index, result)
                    goto continue
                end
            end

            table.insert(results.ok, result)

            ::continue::
        end
    end

    return results, nil
end

--- Auto-repair missing index entries (synchronous).
---@param scan_results huginn.ScanResults
---@return number count number of entries repaired
local function repair_missing_index(scan_results)
    local count = 0
    for _, item in ipairs(scan_results.missing_index) do
        if item.issue.location then
            issue_index.create(item.issue.location.filepath, item.issue_id)
            if item.issue.status == "CLOSED" then
                issue_index.close(item.issue.location.filepath, item.issue_id)
            end
            count = count + 1
        end
    end
    issue_index.flush()
    return count
end

--- Collect all project files for relocation picker.
---@param cwd string absolute path to context root
---@param issue_dir string relative issue directory path
---@return string[] rel_files relative file paths
local function collect_project_files(cwd, issue_dir)
    local abs_issue_dir = filepath.join(cwd, issue_dir)
    local raw = vim.fn.glob(cwd .. "/**/*", false, true)
    local files = {}
    for _, abs_path in ipairs(raw) do
        -- Skip directories
        if not filepath.is_directory(abs_path) then
            -- Skip files inside issue directory
            local norm = filepath.normalize(abs_path)
            local norm_issue = filepath.normalize(abs_issue_dir)
            if norm:sub(1, #norm_issue + 1) ~= norm_issue .. "/" then
                local rel = filepath.absolute_to_relative(norm, cwd)
                if rel then
                    table.insert(files, rel)
                end
            end
        end
    end
    table.sort(files)
    return files
end

--- Check an issue's references against its current file and collect broken ones.
---@param cwd string absolute path to context root
---@param iss huginn.HuginnIssue
---@return string[]|nil broken_refs list of broken ref strings, or nil if none
local function check_refs_after_relocate(cwd, iss)
    if not iss.location or #iss.location.reference == 0 then
        return nil
    end
    local resolve_results = location.resolve(cwd, iss.location)
    if not resolve_results then
        return nil
    end
    local broken = {}
    for ref, res in pairs(resolve_results) do
        if res.result == "not_found" then
            table.insert(broken, ref)
        end
    end
    if #broken > 0 then
        return broken
    end
    return nil
end

--- Fix broken references interactively (async, one ref at a time).
---@param cmd_ctx huginn.CommandContext
---@param items huginn.DoctorResult[]
---@param item_idx number current index into items
---@param ref_idx number current index into current item's broken_refs
---@param on_done fun() callback when all items processed
local function repair_broken_refs(cmd_ctx, items, item_idx, ref_idx, on_done)
    if item_idx > #items then
        on_done()
        return
    end

    local item = items[item_idx]
    if not item.broken_refs or ref_idx > #item.broken_refs then
        repair_broken_refs(cmd_ctx, items, item_idx + 1, 1, on_done)
        return
    end

    local old_ref = item.broken_refs[ref_idx]
    local scope_refs, err = location.find_all_scope_refs(cmd_ctx.cwd, item.rel_filepath)
    if not scope_refs or err then
        cmd_ctx.logger:log("WARN", "Cannot list scopes for " .. item.rel_filepath .. ": " .. (err or "unknown"))
        repair_broken_refs(cmd_ctx, items, item_idx, ref_idx + 1, on_done)
        return
    end

    local skip_sentinel = "-- Skip --"
    local choices = { skip_sentinel }
    for _, ref in ipairs(scope_refs) do
        table.insert(choices, ref)
    end

    vim.ui.select(choices, {
        prompt = "Replace broken ref '" .. old_ref .. "' in issue " .. item.issue_id,
        format_item = function(choice) return choice end,
    }, function(choice)
        if choice and choice ~= skip_sentinel then
            issue.remove_reference(item.issue_id, old_ref)
            issue.add_reference(item.issue_id, choice)
            cmd_ctx.logger:log("INFO", "Replaced ref in " .. item.issue_id .. ": " .. old_ref .. " → " .. choice)
        end
        repair_broken_refs(cmd_ctx, items, item_idx, ref_idx + 1, on_done)
    end)
end

--- Relocate orphaned files interactively (async, one at a time).
--- After each successful relocation, immediately tests references against the
--- new file and prompts for repair if any are broken.
---@param cmd_ctx huginn.CommandContext
---@param items huginn.DoctorResult[]
---@param file_list string[]
---@param idx number current index into items
---@param on_done fun() callback when all items processed
local function repair_missing_files(cmd_ctx, items, file_list, idx, on_done)
    if idx > #items then
        on_done()
        return
    end

    local item = items[idx]
    local skip_sentinel = "-- Skip --"
    local choices = { skip_sentinel }
    for _, f in ipairs(file_list) do
        table.insert(choices, f)
    end

    vim.ui.select(choices, {
        prompt = "Relocate issue " .. item.issue_id .. " (was: " .. item.rel_filepath .. ")",
        format_item = function(choice) return choice end,
    }, function(choice)
        local advance = function()
            repair_missing_files(cmd_ctx, items, file_list, idx + 1, on_done)
        end

        if not choice or choice == skip_sentinel then
            advance()
            return
        end

        local relocated, err = issue.relocate(item.issue_id, choice)
        if err then
            cmd_ctx.logger:log("WARN", "Failed to relocate " .. item.issue_id .. ": " .. err)
            advance()
            return
        end

        cmd_ctx.logger:log("INFO", "Relocated " .. item.issue_id .. " → " .. choice)

        -- Immediately test references against the new file
        local broken = check_refs_after_relocate(cmd_ctx.cwd, relocated)
        if broken then
            local ref_item = {
                issue_id = item.issue_id,
                issue = relocated,
                rel_filepath = choice,
                category = "broken_refs",
                broken_refs = broken,
            }
            repair_broken_refs(cmd_ctx, { ref_item }, 1, 1, advance)
        else
            advance()
        end
    end)
end

--- Run interactive repair on scan results.
---@param cmd_ctx huginn.CommandContext
---@param scan_results huginn.ScanResults
function M.repair(cmd_ctx, scan_results)
    -- Phase 1: Auto-repair missing index (synchronous)
    local index_count = repair_missing_index(scan_results)
    if index_count > 0 then
        cmd_ctx.logger:log("INFO", "Auto-repaired " .. index_count .. " missing index entries")
    end

    -- Phase 2: Relocate orphaned files (async)
    local file_list = collect_project_files(cmd_ctx.cwd, cmd_ctx.config.plugin.issue_dir)

    repair_missing_files(cmd_ctx, scan_results.missing_file, file_list, 1, function()
        -- Phase 3: Fix broken references (async)
        repair_broken_refs(cmd_ctx, scan_results.broken_refs, 1, 1, function()
            -- Phase 4: Cleanup
            annotation.refresh()
            local total_problems = #scan_results.missing_file
                + #scan_results.broken_refs + #scan_results.missing_index
            cmd_ctx.logger:alert("INFO", "Doctor complete: " .. total_problems .. " problem(s) addressed")
        end)
    end)
end

return M
