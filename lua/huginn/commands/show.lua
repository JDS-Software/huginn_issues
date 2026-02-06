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

-- show.lua
-- HuginnShow command: display issues for the current buffer in a floating window


local context = require("huginn.modules.context")
local issue = require("huginn.modules.issue")
local issue_index = require("huginn.modules.issue_index")
local location = require("huginn.modules.location")
local filepath = require("huginn.modules.filepath")
local show_window = require("huginn.components.show_window")

local M = {}

--- Execute the HuginnShow command
---@param opts table opts table from nvim_create_user_command callback
---@return string|nil error error message if the command failed
function M.execute(opts)
    local cmd_ctx, ctx_err = context.from_command(opts)
    if not cmd_ctx then
        return ctx_err
    end

    local rel_filepath = filepath.absolute_to_relative(cmd_ctx.window.filepath, cmd_ctx.cwd)

    -- Resolve cursor location for context-aware filtering
    local loc = location.from_context(cmd_ctx)
    local cursor_refs = {}
    local header_context = rel_filepath
    if loc and #loc.reference > 0 then
        for _, ref in ipairs(loc.reference) do
            cursor_refs[ref] = true
        end
        local _, symbol = location._parse_ref(loc.reference[1])
        if symbol then
            header_context = rel_filepath .. " > " .. symbol
        end
    end

    -- Look up issues for this file
    local entry = issue_index.get(rel_filepath)
    if not entry or not next(entry.issues) then
        cmd_ctx.logger:alert("INFO", "No issues for this file")
        return nil
    end

    -- Read issues relevant to the cursor context
    local issues = {}
    for id, _ in pairs(entry.issues) do
        local iss = issue.read(id)
        if iss and location.is_relevant(iss, cursor_refs) then
            table.insert(issues, iss)
        end
    end

    if #issues == 0 then
        cmd_ctx.logger:alert("INFO", "No issues at this location")
        return nil
    end

    show_window.open({
        issues = issues,
        header_context = header_context,
        source_filepath = rel_filepath,
        source_bufnr = cmd_ctx.buffer,
        context = cmd_ctx,
        is_relevant = function(iss) return location.is_relevant(iss, cursor_refs) end,
    })

    return nil
end

return M
