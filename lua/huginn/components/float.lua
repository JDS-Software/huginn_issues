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

-- float.lua
-- Shared floating window utilities for Huginn UI components


local M = {}

--- Calculate centered floating window configuration.
--- Fixed height mode: uses height_ratio to compute height.
--- Dynamic height mode: uses content_count + content_offset, capped at height_ratio.
---@param opts { width_ratio: number, height_ratio: number, title: string, content_count?: number, content_offset?: number, footer?: table, footer_pos?: string }
---@return table config for nvim_open_win
function M.make_win_opts(opts)
    local width = math.floor(vim.o.columns * opts.width_ratio)
    local height

    if opts.content_count then
        local max_height = math.floor(vim.o.lines * opts.height_ratio)
        local content_height = math.max(opts.content_count, 1) + (opts.content_offset or 0)
        height = math.min(content_height, max_height)
    else
        height = math.floor(vim.o.lines * opts.height_ratio)
    end

    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local win_opts = {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        border = "rounded",
        title = " " .. opts.title .. " ",
        title_pos = "center",
        style = "minimal",
    }

    if opts.footer then
        win_opts.footer = opts.footer
        win_opts.footer_pos = opts.footer_pos or "center"
    end

    return win_opts
end

--- Create a scratch buffer with standard options.
---@param filetype? string optional filetype to set
---@return integer buf buffer handle
function M.create_buf(filetype)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
    if filetype then
        vim.api.nvim_set_option_value("filetype", filetype, { buf = buf })
    end
    return buf
end

--- Register a WinLeave autocmd that prevents focus from escaping to non-floating windows.
---@param group integer augroup handle
---@param buf integer buffer handle
---@param win_id_fn fun(): integer|nil closure returning the current win_id
function M.on_win_leave(group, buf, win_id_fn)
    vim.api.nvim_create_autocmd("WinLeave", {
        group = group,
        buffer = buf,
        callback = function()
            vim.schedule(function()
                local wid = win_id_fn()
                if not wid or not vim.api.nvim_win_is_valid(wid) then
                    return
                end
                local cur_win = vim.api.nvim_get_current_win()
                local cur_config = vim.api.nvim_win_get_config(cur_win)
                if cur_config.relative and cur_config.relative ~= "" then
                    return
                end
                vim.api.nvim_set_current_win(wid)
            end)
        end,
    })
end

--- Register a WinClosed autocmd for cleanup.
---@param group integer augroup handle
---@param win_id integer window handle to watch
---@param augroup_name string augroup name for pcall(del_augroup)
---@param cleanup_fn fun() component-specific teardown
function M.on_win_closed(group, win_id, augroup_name, cleanup_fn)
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        pattern = tostring(win_id),
        once = true,
        callback = function()
            pcall(vim.api.nvim_del_augroup_by_name, augroup_name)
            cleanup_fn()
        end,
    })
end

--- Register a VimResized autocmd that recalculates window geometry.
---@param group integer augroup handle
---@param win_id_fn fun(): integer|nil closure returning the current win_id
---@param recalc_fn fun(): table function returning new win_opts
function M.on_vim_resized(group, win_id_fn, recalc_fn)
    vim.api.nvim_create_autocmd("VimResized", {
        group = group,
        callback = function()
            local wid = win_id_fn()
            if wid and vim.api.nvim_win_is_valid(wid) then
                vim.api.nvim_win_set_config(wid, recalc_fn())
            end
        end,
    })
end

return M
