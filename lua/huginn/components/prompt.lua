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

-- prompt.lua
-- Floating buffer input component for capturing multi-line text


local float = require("huginn.components.float")

local M = {}

---@class huginn.PromptOpts
---@field message string prompt text shown in the window title
---@field default string? pre-filled buffer content (optional)

--- Show a text input prompt in a floating buffer.
--- Calls callback with the input string on submit (<C-s>), or nil on dismissal.
--- When opts is a string, it is treated as { message = opts }.
---@param opts string|huginn.PromptOpts
---@param callback fun(input: string|nil)
function M.show(opts, callback)
    if not callback or type(callback) ~= "function" then
        return
    end

    if type(opts) == "string" then
        opts = { message = opts }
    end

    if type(opts) ~= "table" or not opts.message or opts.message == "" then
        callback(nil)
        return
    end

    -- Create editable scratch buffer
    local buf = float.create_buf("markdown")

    -- Pre-fill default content
    if opts.default and opts.default ~= "" then
        local lines = vim.split(opts.default, "\n")
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    end

    -- Open floating window
    local ok_win, win = pcall(vim.api.nvim_open_win, buf, true, float.make_win_opts({
        width_ratio = 0.6, height_ratio = 0.3, title = opts.message,
    }))
    if not ok_win then
        callback(nil)
        return
    end
    vim.cmd("startinsert")

    -- Guard against double-firing the callback
    local resolved = false

    local function close_win()
        if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end

    local function submit()
        if resolved then return end
        resolved = true
        vim.cmd("stopinsert")
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local content = table.concat(lines, "\n")
        content = content:match("^(.-)%s*$") or ""
        close_win()
        callback(content)
    end

    local function dismiss()
        if resolved then return end
        resolved = true
        vim.cmd("stopinsert")
        close_win()
        callback(nil)
    end

    -- Keymaps: <C-s> submits, <Esc> dismisses
    vim.keymap.set("n", "<C-s>", submit, { buffer = buf, nowait = true })
    vim.keymap.set("i", "<C-s>", submit, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<Esc>", dismiss, { buffer = buf, nowait = true })

    -- Handle external close (e.g., :q) and focus retention
    local group = vim.api.nvim_create_augroup("HuginnPrompt", { clear = true })

    float.on_win_closed(group, win, "HuginnPrompt", function()
        if not resolved then
            resolved = true
            callback(nil)
        end
    end)

    float.on_win_leave(group, buf, function() return win end)
end

return M
