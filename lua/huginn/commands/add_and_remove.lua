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

-- add_and_remove.lua
-- HuginnAdd / HuginnRemove commands: add or remove tree-sitter scope references on existing issues


local context = require("huginn.modules.context")
local issue = require("huginn.modules.issue")
local issue_index = require("huginn.modules.issue_index")
local location = require("huginn.modules.location")
local filepath = require("huginn.modules.filepath")
local annotation = require("huginn.modules.annotation")
local issue_picker = require("huginn.components.issue_picker")

local M = {}

--- Execute the HuginnAdd command
---@param opts table opts table from nvim_create_user_command callback
---@return string|nil error error message if the command failed
function M.execute_add(opts)
    local cmd_ctx, ctx_err = context.from_command(opts)
    if not cmd_ctx then
        return ctx_err
    end

    local loc, loc_err = location.from_context(cmd_ctx)
    if not loc then
        return loc_err
    end

    if #loc.reference == 0 then
        cmd_ctx.logger:alert("WARN", "Cursor is not in a named scope")
        return nil
    end

    local rel_filepath = filepath.absolute_to_relative(cmd_ctx.window.filepath, cmd_ctx.cwd)
    local entry = issue_index.get(rel_filepath)
    if not entry or not next(entry.issues) then
        cmd_ctx.logger:alert("INFO", "No issues for this file")
        return nil
    end

    local cursor_ref = loc.reference[1]

    -- Read all issues, filter to those that do NOT already have this reference
    local issues = {}
    for id, _ in pairs(entry.issues) do
        local iss = issue.read(id)
        if iss then
            local dominated = false
            if iss.location and #iss.location.reference > 0 then
                for _, ref in ipairs(iss.location.reference) do
                    if ref == cursor_ref then
                        dominated = true
                        break
                    end
                end
            end
            if not dominated then
                table.insert(issues, iss)
            end
        end
    end

    if #issues == 0 then
        cmd_ctx.logger:alert("INFO", "All issues already have this reference")
        return nil
    end

    local _, symbol = location._parse_ref(cursor_ref)
    local header_context = "Add: " .. rel_filepath .. " > " .. (symbol or cursor_ref)

    issue_picker.open({
        issues = issues,
        header_context = header_context,
        context = cmd_ctx,
    }, function(issue_id)
        if not issue_id then return end

        local _, add_err = issue.add_reference(issue_id, cursor_ref)
        if add_err then
            cmd_ctx.logger:alert("ERROR", "Failed to add reference: " .. add_err)
            return
        end

        cmd_ctx.logger:alert("INFO", "Reference added to " .. issue_id)
        annotation.refresh()
    end)

    return nil
end

--- Execute the HuginnRemove command
---@param opts table opts table from nvim_create_user_command callback
---@return string|nil error error message if the command failed
function M.execute_remove(opts)
    local cmd_ctx, ctx_err = context.from_command(opts)
    if not cmd_ctx then
        return ctx_err
    end

    local loc, loc_err = location.from_context(cmd_ctx)
    if not loc then
        return loc_err
    end

    if #loc.reference == 0 then
        cmd_ctx.logger:alert("WARN", "Cursor is not in a named scope")
        return nil
    end

    local rel_filepath = filepath.absolute_to_relative(cmd_ctx.window.filepath, cmd_ctx.cwd)
    local entry = issue_index.get(rel_filepath)
    if not entry or not next(entry.issues) then
        cmd_ctx.logger:alert("INFO", "No issues for this file")
        return nil
    end

    local cursor_ref = loc.reference[1]

    -- Read all issues, filter to those that DO have this reference
    local issues = {}
    for id, _ in pairs(entry.issues) do
        local iss = issue.read(id)
        if iss then
            if iss.location and #iss.location.reference > 0 then
                for _, ref in ipairs(iss.location.reference) do
                    if ref == cursor_ref then
                        table.insert(issues, iss)
                        break
                    end
                end
            end
        end
    end

    if #issues == 0 then
        cmd_ctx.logger:alert("INFO", "No issues have this reference")
        return nil
    end

    local _, symbol = location._parse_ref(cursor_ref)
    local header_context = "Remove: " .. rel_filepath .. " > " .. (symbol or cursor_ref)

    issue_picker.open({
        issues = issues,
        header_context = header_context,
        context = cmd_ctx,
    }, function(issue_id)
        if not issue_id then return end

        local _, remove_err = issue.remove_reference(issue_id, cursor_ref)
        if remove_err then
            cmd_ctx.logger:alert("ERROR", "Failed to remove reference: " .. remove_err)
            return
        end

        cmd_ctx.logger:alert("INFO", "Reference removed from " .. issue_id)
        annotation.refresh()
    end)

    return nil
end

return M
