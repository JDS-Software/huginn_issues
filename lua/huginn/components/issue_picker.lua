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

-- issue_picker.lua
-- Floating window component for selecting an issue from a filtered list (callback-based)


local issue_mod = require("huginn.modules.issue")
local float = require("huginn.components.float")
local issue_filter = require("huginn.components.issue_filter")

local M = {}

local AUGROUP_NAME = "HuginnIssuePicker"
local HELP_TEXT = "Enter select  q cancel  C-f filter"

-- ──────────────────────────────────────────────────────────────────────
-- Picker: encapsulates the lifecycle of a single picker window instance.
-- ──────────────────────────────────────────────────────────────────────

---@class huginn.IssuePicker
---@field win_id integer|nil
---@field buf_id integer|nil
---@field issues huginn.HuginnIssue[]
---@field display_issues huginn.HuginnIssue[]
---@field line_map table<integer, string>  line number -> issue ID
---@field filter string "all"|"open"|"closed"
---@field header_context string left-aligned header text
---@field context huginn.CommandContext command context
---@field callback fun(issue_id: string|nil)|nil selection callback
---@field resolved boolean double-fire guard
local Picker = {}
Picker.__index = Picker

--- Create an inert Picker value — nothing is allocated until :activate()
---@param opts table { issues, header_context, context }
---@param callback fun(issue_id: string|nil)|nil
---@return huginn.IssuePicker
function Picker.new(opts, callback)
    local self = setmetatable({}, Picker)
    self.win_id = nil
    self.buf_id = nil
    self.issues = opts.issues or {}
    self.display_issues = {}
    self.line_map = {}
    self.filter = "all"
    self.header_context = opts.header_context or ""
    self.context = opts.context
    self.callback = callback
    self.resolved = false

    table.sort(self.issues, function(a, b) return a.id < b.id end)
    return self
end

-- ── Queries (no mutation) ──────────────────────────────────────────

--- Is the Neovim window still alive?
---@return boolean
function Picker:is_valid()
    return self.win_id ~= nil and vim.api.nvim_win_is_valid(self.win_id)
end

--- Floating-window geometry for nvim_open_win / nvim_win_set_config
---@param issue_count number
---@return table
function Picker:make_win_opts(issue_count)
    return float.make_win_opts({
        width_ratio = 0.8,
        height_ratio = 0.5,
        title = "Huginn Pick",
        content_count = issue_count,
        content_offset = 4,
    })
end

--- Issue ID on the line where the cursor currently sits, or nil
---@return string|nil
function Picker:issue_id_at_cursor()
    if not self:is_valid() then return nil end
    local cursor = vim.api.nvim_win_get_cursor(self.win_id)
    return self.line_map[cursor[1]]
end

-- ── Pure helpers (no self, no mutation) ────────────────────────────

-- ── Mutations ──────────────────────────────────────────────────────

--- Rewrite the buffer to reflect the current issues + filter.
--- Updates self.display_issues and self.line_map as a side-effect.
function Picker:render()
    if not self.buf_id or not vim.api.nvim_buf_is_valid(self.buf_id) then return end
    if not self:is_valid() then return end

    self.display_issues = issue_filter.apply(self.issues, self.filter)
    self.line_map = {}

    local win_width = vim.api.nvim_win_get_width(self.win_id)

    -- Header
    local filter_label = "[Filter: " .. issue_filter.FILTER_LABELS[self.filter] .. "]"
    local padding = math.max(win_width - #self.header_context - #filter_label, 1)
    local header = self.header_context .. string.rep(" ", padding) .. filter_label

    -- Separator
    local separator = string.rep("─", win_width)

    local lines = { header, separator }

    if #self.display_issues == 0 then
        local msg = "(no issues match filter)"
        local pad = math.max(math.floor((win_width - #msg) / 2), 0)
        table.insert(lines, string.rep(" ", pad) .. msg)
    else
        for _, iss in ipairs(self.display_issues) do
            local id_str = string.format("%-16s", iss.id)
            local status_str = string.format("%-9s", "[" .. iss.status .. "]")
            local desc_str = issue_mod.get_ui_description(self.context, iss)

            table.insert(lines, id_str .. status_str .. desc_str)
            self.line_map[#lines] = iss.id
        end
    end

    -- Footer: separator + keyboard shortcuts
    table.insert(lines, string.rep("─", win_width))
    local help_pad = math.max(math.floor((win_width - #HELP_TEXT) / 2), 0)
    table.insert(lines, string.rep(" ", help_pad) .. HELP_TEXT)

    vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf_id })
    vim.api.nvim_buf_set_lines(self.buf_id, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf_id })

    vim.api.nvim_win_set_config(self.win_id, self:make_win_opts(#self.display_issues))
end

--- Ensure the cursor stays within the issue line range (line 3 to last issue line)
function Picker:clamp_cursor()
    if not self:is_valid() then return end
    local line_count = vim.api.nvim_buf_line_count(self.buf_id)
    local cursor = vim.api.nvim_win_get_cursor(self.win_id)
    -- Issue lines: 3 through line_count - 2 (last 2 lines are footer separator + help)
    local last_issue_line = math.max(line_count - 2, 3)
    if cursor[1] > last_issue_line then
        vim.api.nvim_win_set_cursor(self.win_id, { last_issue_line, 0 })
    elseif cursor[1] < 3 and line_count >= 3 then
        vim.api.nvim_win_set_cursor(self.win_id, { 3, 0 })
    end
end

--- Cycle the filter to the next value and re-render
function Picker:cycle_filter()
    self.filter = issue_filter.next(self.filter)
    self:render()
    if self:is_valid() then
        local line_count = vim.api.nvim_buf_line_count(self.buf_id)
        if line_count >= 3 then
            vim.api.nvim_win_set_cursor(self.win_id, { 3, 0 })
        end
    end
end

--- Fire the callback with the selected issue ID and close
function Picker:select()
    local issue_id = self:issue_id_at_cursor()
    if not issue_id then return end

    if self.resolved then return end
    self.resolved = true

    M.close()

    if self.callback then
        self.callback(issue_id)
    end
end

--- Dismiss the picker (close without selecting)
function Picker:dismiss()
    if self.resolved then return end
    self.resolved = true

    M.close()

    if self.callback then
        self.callback(nil)
    end
end

--- Create the Neovim buffer + window and wire up keymaps / autocmds
function Picker:activate()
    -- Buffer
    self.buf_id = float.create_buf("huginnpick")

    -- Window
    local ok_win, wid = pcall(vim.api.nvim_open_win, self.buf_id, true, self:make_win_opts(#self.issues))
    if not ok_win then
        self.buf_id = nil
        return
    end
    self.win_id = wid
    vim.api.nvim_set_option_value("cursorline", true, { win = self.win_id })
    vim.api.nvim_set_option_value("number", false, { win = self.win_id })
    vim.api.nvim_set_option_value("relativenumber", false, { win = self.win_id })

    self:render()

    local line_count = vim.api.nvim_buf_line_count(self.buf_id)
    if line_count >= 3 then
        vim.api.nvim_win_set_cursor(self.win_id, { 3, 0 })
    end

    self:bind_keys()
    self:bind_autocmds()
end

--- Destroy the Neovim window (if live) and wipe autocmds.
--- Does NOT fire callback — callers handle callback before deactivate.
function Picker:deactivate()
    if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
        vim.api.nvim_win_close(self.win_id, true)
    end
    pcall(vim.api.nvim_del_augroup_by_name, AUGROUP_NAME)
    self.win_id = nil
    self.buf_id = nil
end

--- Register buffer-local keymaps
function Picker:bind_keys()
    local buf = self.buf_id
    if not buf then return end

    vim.keymap.set("n", "q", function() self:dismiss() end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<Esc>", function() self:dismiss() end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<CR>", function() self:select() end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<C-f>", function() self:cycle_filter() end, { buffer = buf, nowait = true })
end

--- Register autocmds (resize, close cleanup, cursor clamp)
function Picker:bind_autocmds()
    local group = vim.api.nvim_create_augroup(AUGROUP_NAME, { clear = true })

    float.on_vim_resized(group, function() return self.win_id end, function()
        return self:make_win_opts(#self.display_issues)
    end)

    float.on_win_closed(group, self.win_id, AUGROUP_NAME, function()
        -- Fire callback(nil) if not already resolved (external close, e.g. :q)
        if not self.resolved then
            self.resolved = true
            if self.callback then
                self.callback(nil)
            end
        end
        self.win_id = nil
        self.buf_id = nil
    end)

    vim.api.nvim_create_autocmd("CursorMoved", {
        group = group,
        buffer = self.buf_id,
        callback = function() self:clamp_cursor() end,
    })

    float.on_win_leave(group, self.buf_id, function() return self.win_id end)
end

-- ──────────────────────────────────────────────────────────────────────
-- Module-level API: manages the singleton Picker instance
-- ──────────────────────────────────────────────────────────────────────

---@type huginn.IssuePicker|nil
local active_picker = nil

--- Open the issue picker.
--- If a picker is already open and valid, focuses it instead of creating a new one.
---@param opts table { issues, header_context, context }
---@param callback fun(issue_id: string|nil)|nil called with selected issue ID or nil on dismiss
function M.open(opts, callback)
    if not callback or type(callback) ~= "function" then
        return
    end

    if type(opts) ~= "table" or not opts.issues or #opts.issues == 0 then
        callback(nil)
        return
    end

    if active_picker and active_picker:is_valid() then
        vim.api.nvim_set_current_win(active_picker.win_id)
        return
    end

    -- Tear down any stale instance before creating a new one
    if active_picker then
        active_picker:deactivate()
    end

    active_picker = Picker.new(opts, callback)
    active_picker:activate()
end

--- Close the active picker (if any) and release the instance.
--- Does NOT fire callback — the select/dismiss/WinClosed paths handle that.
function M.close()
    if active_picker then
        active_picker:deactivate()
        active_picker = nil
    end
end

--- Check whether the picker is currently open and valid
---@return boolean
function M.is_open()
    return active_picker ~= nil and active_picker:is_valid()
end

--- Close and reset (testing escape hatch)
function M._close()
    M.close()
end

--- Get the active Picker instance (testing only)
---@return huginn.IssuePicker|nil
function M._get_picker()
    return active_picker
end

return M
