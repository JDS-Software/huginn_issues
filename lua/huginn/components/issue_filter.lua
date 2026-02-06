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

-- issue_filter.lua
-- Shared issue filter cycling logic for Huginn UI components


local M = {}

M.FILTER_CYCLE = { "all", "open", "closed" }
M.FILTER_LABELS = { all = "ALL", open = "OPEN", closed = "CLOSED" }

--- Filter an issue list by status keyword.
---@param issues huginn.HuginnIssue[]
---@param filter string "all"|"open"|"closed"
---@return huginn.HuginnIssue[]
function M.apply(issues, filter)
    if filter == "all" then return vim.deepcopy(issues) end
    local target = filter == "open" and "OPEN" or "CLOSED"
    local out = {}
    for _, iss in ipairs(issues) do
        if iss.status == target then table.insert(out, iss) end
    end
    return out
end

--- Advance to the next filter in the cycle.
---@param current string
---@return string
function M.next(current)
    for i, f in ipairs(M.FILTER_CYCLE) do
        if f == current then
            return M.FILTER_CYCLE[(i % #M.FILTER_CYCLE) + 1]
        end
    end
    return "all"
end

return M
