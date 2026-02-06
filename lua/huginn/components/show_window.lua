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

-- show_window.lua
-- Floating window component for displaying issues associated with the current buffer


local issue_mod = require("huginn.modules.issue")
local issue_index = require("huginn.modules.issue_index")
local issue_window = require("huginn.components.issue_window")
local annotation = require("huginn.modules.annotation")
local prompt = require("huginn.components.prompt")
local float = require("huginn.components.float")
local issue_filter = require("huginn.components.issue_filter")

local M = {}

local AUGROUP_NAME = "HuginnShowWindow"
local HELP_TEXT = "Enter open  q close  C-f filter  C-r resolve/reopen  C-d delete"

-- ──────────────────────────────────────────────────────────────────────
-- Window: encapsulates the lifecycle of a single show-window instance.
-- A new Window is created on each M.open() call; the previous one (if
-- any) is closed first.  All mutation flows through methods on this
-- object, so there is a single, auditable surface for state changes.
-- ──────────────────────────────────────────────────────────────────────

---@class huginn.ShowWindow
---@field win_id integer|nil
---@field buf_id integer|nil
---@field issues huginn.HuginnIssue[]
---@field display_issues huginn.HuginnIssue[]
---@field line_map table<integer, string>  line number -> issue ID
---@field filter string "all"|"open"|"closed"
---@field source_filepath string relative filepath used for index lookups
---@field source_bufnr integer buffer number of the source file
---@field header_context string left-aligned header text
---@field context huginn.CommandContext command context
---@field is_relevant fun(iss: huginn.HuginnIssue): boolean|nil relevance predicate from caller
local Window = {}
Window.__index = Window

--- Create an inert Window value — nothing is allocated until :activate()
---@param opts table { issues, header_context, source_filepath, source_bufnr, context }
---@return huginn.ShowWindow
function Window.new(opts)
    local self = setmetatable({}, Window)
    self.win_id = nil
    self.buf_id = nil
    self.issues = opts.issues or {}
    self.display_issues = {}
    self.line_map = {}
    self.filter = "all"
    self.source_filepath = opts.source_filepath or ""
    self.source_bufnr = opts.source_bufnr or 0
    self.header_context = opts.header_context or ""
    self.context = opts.context
    self.is_relevant = opts.is_relevant

    table.sort(self.issues, function(a, b) return a.id < b.id end)
    return self
end

-- ── Queries (no mutation) ──────────────────────────────────────────

--- Is the Neovim window still alive?
---@return boolean
function Window:is_valid()
    return self.win_id ~= nil and vim.api.nvim_win_is_valid(self.win_id)
end

--- Floating-window geometry for nvim_open_win / nvim_win_set_config
---@param issue_count number
---@return table
function Window:make_win_opts(issue_count)
    return float.make_win_opts({
        width_ratio = 0.8,
        height_ratio = 0.5,
        title = "Huginn Show",
        content_count = issue_count,
        content_offset = 4,
    })
end

--- Issue ID on the line where the cursor currently sits, or nil
---@return string|nil
function Window:issue_id_at_cursor()
    if not self:is_valid() then return nil end
    local cursor = vim.api.nvim_win_get_cursor(self.win_id)
    return self.line_map[cursor[1]]
end

-- ── Pure helpers (no self, no mutation) ────────────────────────────

-- ── Mutations ──────────────────────────────────────────────────────

--- Rewrite the buffer to reflect the current issues + filter.
--- Updates self.display_issues and self.line_map as a side-effect.
function Window:render()
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

--- Re-read issues from the index and update self.issues.
--- Returns false if no issues remain for the file.
---@return boolean has_issues
function Window:reload_issues()
    local entry = issue_index.get(self.source_filepath)
    if not entry or not next(entry.issues) then
        return false
    end

    local issues = {}
    for id, _ in pairs(entry.issues) do
        local iss = issue_mod.read(id)
        if iss and (not self.is_relevant or self.is_relevant(iss)) then
            table.insert(issues, iss)
        end
    end
    if #issues == 0 then
        return false
    end

    table.sort(issues, function(a, b) return a.id < b.id end)
    self.issues = issues
    return true
end

--- Re-read issues from the index, update self.issues, and re-render.
--- Closes the window if no issues remain for the file.
function Window:refresh()
    if not self:reload_issues() then
        M.close()
        return
    end

    self:render()
    self:clamp_cursor()
end

--- Ensure the cursor stays within the issue line range (line 3 to last issue line)
function Window:clamp_cursor()
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
function Window:cycle_filter()
    self.filter = issue_filter.next(self.filter)
    self:render()
    if self:is_valid() then
        local line_count = vim.api.nvim_buf_line_count(self.buf_id)
        if line_count >= 3 then
            vim.api.nvim_win_set_cursor(self.win_id, { 3, 0 })
        end
    end
end

--- Toggle the status of the issue under the cursor.
--- OPEN issues prompt for a resolution description before closing.
--- CLOSED issues are reopened immediately.
function Window:toggle_status()
    local issue_id = self:issue_id_at_cursor()
    if not issue_id then return end

    local iss = issue_mod.read(issue_id)
    if not iss then return end

    if iss.status == "OPEN" then
        prompt.show("Issue Resolution", function(input)
            if input == nil then return end
            issue_mod.resolve(issue_id, input)
            self:refresh()
            self:refresh_annotations()
        end)
    else
        issue_mod.reopen(issue_id)
        self:refresh()
        self:refresh_annotations()
    end
end

--- Delete the issue under the cursor.
--- Delegates to issue.delete which owns the confirmation dialog.
function Window:delete_issue()
    local issue_id = self:issue_id_at_cursor()
    if not issue_id then return end

    issue_mod.delete(issue_id, function(deleted)
        if not deleted then return end
        self:refresh()
        self:refresh_annotations()
    end)
end

--- Open the issue window for the issue under the cursor.
--- The show window is deactivated (not destroyed) so it can be restored
--- when the user dismisses the issue window with Esc.
function Window:open_issue()
    local id = self:issue_id_at_cursor()
    if not id then return end

    local cursor_line = vim.api.nvim_win_get_cursor(self.win_id)[1]

    self:deactivate()

    issue_window.open(id, {
        on_dismiss = function()
            if self:reload_issues() then
                self:activate()
                -- Restore cursor to the issue line it was on before
                if self:is_valid() then
                    local line_count = vim.api.nvim_buf_line_count(self.buf_id)
                    local last_issue_line = math.max(line_count - 2, 3)
                    local target = math.max(3, math.min(cursor_line, last_issue_line))
                    vim.api.nvim_win_set_cursor(self.win_id, { target, 0 })
                end
            else
                active_window = nil
            end
        end,
        on_quit = function()
            active_window = nil
        end,
    })
end

--- Re-annotate the source buffer if it is still valid
function Window:refresh_annotations()
    if self.source_bufnr and vim.api.nvim_buf_is_valid(self.source_bufnr) then
        annotation.annotate(self.source_bufnr)
    end
end

--- Create the Neovim buffer + window and wire up keymaps / autocmds
function Window:activate()
    -- Buffer
    self.buf_id = float.create_buf("huginnshow")

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

--- Destroy the Neovim window (if live) and wipe autocmds
function Window:deactivate()
    if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
        vim.api.nvim_win_close(self.win_id, true)
    end
    pcall(vim.api.nvim_del_augroup_by_name, AUGROUP_NAME)
    self.win_id = nil
    self.buf_id = nil
end

--- Register buffer-local keymaps
function Window:bind_keys()
    local buf = self.buf_id
    if not buf then return end

    vim.keymap.set("n", "q", function() M.close() end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<Esc>", function() M.close() end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<CR>", function() self:open_issue() end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<C-r>", function() self:toggle_status() end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<C-d>", function() self:delete_issue() end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<C-f>", function() self:cycle_filter() end, { buffer = buf, nowait = true })
end

--- Register autocmds (resize, close cleanup, cursor clamp)
function Window:bind_autocmds()
    local group = vim.api.nvim_create_augroup(AUGROUP_NAME, { clear = true })

    float.on_vim_resized(group, function() return self.win_id end, function()
        return self:make_win_opts(#self.display_issues)
    end)

    float.on_win_closed(group, self.win_id, AUGROUP_NAME, function()
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
-- Module-level API: manages the singleton Window instance
-- ──────────────────────────────────────────────────────────────────────

---@type huginn.ShowWindow|nil
local active_window = nil

--- Open the show window.
--- If a window is already open and valid, focuses it instead of creating a new one.
---@param opts table { issues, header_context, source_filepath, source_bufnr, context }
function M.open(opts)
    if active_window and active_window:is_valid() then
        vim.api.nvim_set_current_win(active_window.win_id)
        return
    end

    -- Tear down any stale instance before creating a new one
    if active_window then
        active_window:deactivate()
    end

    active_window = Window.new(opts)
    active_window:activate()
end

--- Close the active show window (if any) and release the instance
function M.close()
    if active_window then
        active_window:deactivate()
        active_window = nil
    end
end

--- Check whether the show window is currently open and valid
---@return boolean
function M.is_open()
    return active_window ~= nil and active_window:is_valid()
end

--- Close and reset (testing escape hatch)
function M._close()
    M.close()
end

--- Get the active Window instance (testing only)
---@return huginn.ShowWindow|nil
function M._get_window()
    return active_window
end

return M
