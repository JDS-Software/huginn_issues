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

-- log_viewer.lua
-- Floating window component for displaying the in-memory log buffer


local float = require("huginn.components.float")

local M = {}

local win_id = nil
local buf_id = nil

--- Read log buffer and write lines into the scratch buffer
---@param logger huginn.Logger
local function populate_buffer(logger)
    if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
        return
    end

    local lines = logger:get_buffer()
    if #lines == 0 then
        lines = { "[No log entries]" }
    end

    vim.api.nvim_set_option_value("modifiable", true, { buf = buf_id })
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf_id })

    -- Move cursor to last line
    if win_id and vim.api.nvim_win_is_valid(win_id) then
        vim.api.nvim_win_set_cursor(win_id, { #lines, 0 })
    end
end

--- Close the viewer window and nil out state
local function close()
    if win_id and vim.api.nvim_win_is_valid(win_id) then
        vim.api.nvim_win_close(win_id, true)
    end
    pcall(vim.api.nvim_del_augroup_by_name, "HuginnLogViewer")
    win_id = nil
    buf_id = nil
end

--- Set buffer-local keymaps for the viewer
---@param logger huginn.Logger
local function set_keymaps(logger)
    if not buf_id then
        return
    end

    vim.keymap.set("n", "q", close, { buffer = buf_id, nowait = true })
    vim.keymap.set("n", "<C-r>", function()
        populate_buffer(logger)
    end, { buffer = buf_id, nowait = true })
end

--- Open the log viewer floating window
--- If already open, focuses the existing window.
---@param logger huginn.Logger
function M.open(logger)
    -- If window already open and valid, focus it
    if win_id and vim.api.nvim_win_is_valid(win_id) then
        vim.api.nvim_set_current_win(win_id)
        return
    end

    -- Create scratch buffer
    buf_id = float.create_buf("huginnlog")

    -- Open floating window
    local function current_win_opts()
        return float.make_win_opts({ width_ratio = 0.8, height_ratio = 0.8, title = "Huginn Log" })
    end
    local ok_win, wid = pcall(vim.api.nvim_open_win, buf_id, true, current_win_opts())
    if not ok_win then
        buf_id = nil
        return
    end
    win_id = wid

    -- Populate and configure
    populate_buffer(logger)
    set_keymaps(logger)

    -- Autocmds: resize, close cleanup, focus retention
    local group = vim.api.nvim_create_augroup("HuginnLogViewer", { clear = true })
    local win_id_fn = function() return win_id end

    float.on_vim_resized(group, win_id_fn, current_win_opts)

    float.on_win_closed(group, win_id, "HuginnLogViewer", function()
        win_id = nil
        buf_id = nil
    end)

    float.on_win_leave(group, buf_id, win_id_fn)
end

--- Check whether the viewer window is currently open and valid
---@return boolean
function M.is_open()
    return win_id ~= nil and vim.api.nvim_win_is_valid(win_id)
end

--- Close the viewer and reset state (testing escape hatch)
function M._close()
    close()
end

return M
