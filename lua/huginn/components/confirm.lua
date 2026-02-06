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

-- confirm.lua
-- Generic yes/no confirmation dialog using vim.ui.select


local M = {}

---@alias huginn.ConfirmLevel "safe"|"caution"|"danger"

---@class huginn.ConfirmOpts
---@field message string the question to display to the user
---@field level huginn.ConfirmLevel? severity level (default: "safe")

--- Format the prompt string with level prefix
---@param level huginn.ConfirmLevel
---@param message string
---@return string
local function format_prompt(level, message)
    local labels = {
        safe = "Safe",
        caution = "Caution",
        danger = "Danger",
    }
    local label = labels[level] or "Safe"
    return "[" .. label .. "] " .. message
end

--- Show a yes/no confirmation dialog
--- Calls callback with true if user selects "Yes", false for "No" or dismissal.
--- When opts is a string, it is treated as { message = opts, level = "safe" }.
---@param opts string|huginn.ConfirmOpts a message string, or an options table
---@param callback fun(confirmed: boolean) called with true for "Yes", false otherwise
function M.show(opts, callback)
    if not callback or type(callback) ~= "function" then
        return
    end

    if type(opts) == "string" then
        opts = { message = opts }
    end

    if type(opts) ~= "table" or not opts.message or opts.message == "" then
        callback(false)
        return
    end

    local level = opts.level or "safe"
    local prompt = format_prompt(level, opts.message)

    vim.ui.select({ "Yes", "No" }, {
        prompt = prompt,
    }, function(choice)
        callback(choice == "Yes")
    end)
end

return M
