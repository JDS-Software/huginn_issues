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

-- create.lua
-- HuginnCreate command: create a new issue from the current buffer position


local context = require("huginn.modules.context")
local issue = require("huginn.modules.issue")
local location = require("huginn.modules.location")
local filepath = require("huginn.modules.filepath")
local prompt = require("huginn.components.prompt")
local annotation = require("huginn.modules.annotation")

local M = {}

--- Execute the HuginnCreate command
---@param opts table opts table from nvim_create_user_command callback
---@return string|nil error error message if the command failed
function M.execute(opts)
    -- Capture editor state in one call
    local cmd_ctx, ctx_err = context.from_command(opts)
    if not cmd_ctx then
        return ctx_err
    end

    -- Extract location (fall back to file-scoped on failure)
    local loc, loc_err = location.from_context(cmd_ctx)
    if not loc then
        cmd_ctx.logger:log("WARN", "Location extraction failed: " .. loc_err)
        local rel_path = filepath.absolute_to_relative(cmd_ctx.window.filepath, cmd_ctx.cwd)
        loc = { filepath = rel_path, reference = {} }
    end

    -- Prompt for description; issue creation happens in the callback
    prompt.show("Issue Description", function(description)
        -- Dismissal: abort
        if description == nil then return end

        -- Create issue (empty string is valid — no description block)
        local new_issue, create_err = issue.create(loc, description)
        if not new_issue then
            cmd_ctx.logger:alert("ERROR", "Failed to create issue: " .. create_err)
            return
        end

        cmd_ctx.logger:alert("INFO", "Created issue: " .. new_issue.id)
        annotation.refresh()

        -- Optionally open the Issue.md
        if cmd_ctx.config.issue and cmd_ctx.config.issue.open_after_create then
            local issue_path = issue.issue_path(new_issue.id)
            if issue_path then
                vim.cmd("edit " .. vim.fn.fnameescape(issue_path))
            end
        end
    end)
end

return M
