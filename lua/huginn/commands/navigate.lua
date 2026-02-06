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

-- navigate.lua
-- HuginnNext / HuginnPrevious commands: cycle cursor through issue locations


local context = require("huginn.modules.context")
local issue = require("huginn.modules.issue")
local issue_index = require("huginn.modules.issue_index")
local location = require("huginn.modules.location")
local filepath = require("huginn.modules.filepath")

local M = {}

--- Collect deduplicated, sorted, 0-indexed line numbers for all open issues in the current buffer.
---@param cmd_ctx huginn.CommandContext
---@return integer[]|nil lines sorted 0-indexed line numbers, or nil when none found (user already notified)
local function collect_issue_lines(cmd_ctx)
    local rel_filepath = filepath.absolute_to_relative(cmd_ctx.window.filepath, cmd_ctx.cwd)

    local entry = issue_index.get(rel_filepath)
    if not entry or not next(entry.issues) then
        cmd_ctx.logger:alert("INFO", "No issues for this file")
        return nil
    end

    -- Collect open issue IDs (index stores lowercase "open"/"closed")
    local open_ids = {}
    for id, status in pairs(entry.issues) do
        if status == "open" then
            table.insert(open_ids, id)
        end
    end

    if #open_ids == 0 then
        cmd_ctx.logger:alert("INFO", "No open issues for this file")
        return nil
    end

    -- Resolve line numbers for each open issue
    local line_set = {}
    for _, id in ipairs(open_ids) do
        local iss = issue.read(id)
        if iss then
            if not iss.location or #iss.location.reference == 0 then
                -- File-scoped issue: line 0
                line_set[0] = true
            else
                local results = location.resolve(cmd_ctx.cwd, iss.location)
                if results then
                    local any_found = false
                    for _, res in pairs(results) do
                        if res.result == "found" and res.node then
                            local start_row = res.node:range()
                            line_set[start_row] = true
                            any_found = true
                        end
                    end
                    if not any_found then
                        -- Unresolvable references: treat as file-scoped
                        line_set[0] = true
                    end
                else
                    -- Resolution failed: treat as file-scoped
                    line_set[0] = true
                end
            end
        end
    end

    -- Convert set to sorted list
    local lines = {}
    for line in pairs(line_set) do
        table.insert(lines, line)
    end

    if #lines == 0 then
        cmd_ctx.logger:alert("INFO", "No issue locations found")
        return nil
    end

    table.sort(lines)
    return lines
end

--- Navigate to the next or previous issue location in the current buffer.
---@param opts table opts table from nvim_create_user_command callback
---@param direction "next"|"previous"
---@return string|nil error
local function navigate(opts, direction)
    local cmd_ctx, ctx_err = context.from_command(opts)
    if not cmd_ctx then
        return ctx_err
    end

    local lines = collect_issue_lines(cmd_ctx)
    if not lines then
        return nil
    end

    -- Current cursor line (convert 1-based to 0-based)
    local cursor_line = cmd_ctx.window.start.line - 1

    local target
    if direction == "next" then
        -- Find first entry strictly greater than cursor line
        for _, line in ipairs(lines) do
            if line > cursor_line then
                target = line
                break
            end
        end
        -- Wrap to first
        if not target then
            target = lines[1]
        end
    else
        -- Find last entry strictly less than cursor line
        for i = #lines, 1, -1 do
            if lines[i] < cursor_line then
                target = lines[i]
                break
            end
        end
        -- Wrap to last
        if not target then
            target = lines[#lines]
        end
    end

    -- Move cursor (convert 0-based to 1-based)
    vim.api.nvim_win_set_cursor(0, { target + 1, 0 })
    vim.cmd("normal! ^")

    return nil
end

--- Execute HuginnNext: jump to the next issue location in the current buffer
---@param opts table opts table from nvim_create_user_command callback
---@return string|nil error
function M.execute_next(opts)
    return navigate(opts, "next")
end

--- Execute HuginnPrevious: jump to the previous issue location in the current buffer
---@param opts table opts table from nvim_create_user_command callback
---@return string|nil error
function M.execute_previous(opts)
    return navigate(opts, "previous")
end

return M
