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

-- home_window.lua
-- Floating window component for displaying all project files with issues


local issue_mod = require("huginn.modules.issue")
local location = require("huginn.modules.location")
local filepath = require("huginn.modules.filepath")
local float = require("huginn.components.float")
local issue_filter = require("huginn.components.issue_filter")

local M = {}

local AUGROUP_NAME = "HuginnHomeWindow"
local HELP_TEXT = "Enter open  q close  C-f filter  C-n/C-p/arrows navigate"
local DEBOUNCE_MS = 150

-- ── Pure helpers ────────────────────────────────────────────────────

--- Case-insensitive subsequence match
---@param str string
---@param query string
---@return boolean
local function fuzzy_match(str, query)
    if query == "" then return true end
    local lower_str = str:lower()
    local lower_query = query:lower()
    local si = 1
    for qi = 1, #lower_query do
        local ch = lower_query:sub(qi, qi)
        local found = lower_str:find(ch, si, true)
        if not found then return false end
        si = found + 1
    end
    return true
end


--- Count issues in an IndexEntry matching the filter
---@param entry huginn.IndexEntry
---@param filter string "all"|"open"|"closed"
---@return integer
local function count_matching_issues(entry, filter)
    local count = 0
    for _, status in pairs(entry.issues) do
        if filter == "all" or status == filter then
            count = count + 1
        end
    end
    return count
end

--- Filter and sort entries into display list
---@param entries table<string, huginn.IndexEntry>
---@param filter string
---@param query string
---@return table[] list of { filepath, count }
local function build_display_entries(entries, filter, query)
    local result = {}
    for fp, entry in pairs(entries) do
        local count = count_matching_issues(entry, filter)
        if count > 0 and fuzzy_match(fp, query) then
            table.insert(result, { filepath = fp, count = count })
        end
    end
    table.sort(result, function(a, b) return a.filepath < b.filepath end)
    return result
end

--- Build flat visible_rows list from display_entries and expansion state
---@param display_entries table[]
---@param expanded_filepath string|nil
---@param expanded_issues table[]
---@return table[] visible_rows
local function build_visible_rows(display_entries, expanded_filepath, expanded_issues)
    local rows = {}
    for _, entry in ipairs(display_entries) do
        table.insert(rows, { type = "file", filepath = entry.filepath, count = entry.count })
        if entry.filepath == expanded_filepath then
            for _, iss in ipairs(expanded_issues) do
                table.insert(rows, {
                    type = "issue",
                    filepath = entry.filepath,
                    issue_id = iss.id,
                    description = iss.description,
                    reference = iss.reference,
                })
            end
        end
    end
    return rows
end

-- ── Window class ────────────────────────────────────────────────────

---@class huginn.HomeWindow
---@field win_id integer|nil
---@field buf_id integer|nil
---@field entries table<string, huginn.IndexEntry>
---@field display_entries table[]
---@field visible_rows table[]
---@field line_map table<integer, table>
---@field filter string
---@field query string
---@field selected_index integer
---@field expanded_filepath string|nil
---@field expanded_issues table[]
---@field context huginn.CommandContext
---@field ns_id integer
---@field _debounce_timer uv_timer_t|nil
local Window = {}
Window.__index = Window

--- Create an inert Window value
---@param opts table { entries, context }
---@return huginn.HomeWindow
function Window.new(opts)
    local self = setmetatable({}, Window)
    self.win_id = nil
    self.buf_id = nil
    self.entries = opts.entries or {}
    self.display_entries = {}
    self.visible_rows = {}
    self.line_map = {}
    self.filter = "all"
    self.query = ""
    self.selected_index = 1
    self.expanded_filepath = nil
    self.expanded_issues = {}
    self.context = opts.context
    self.ns_id = vim.api.nvim_create_namespace("huginn_home_selection")
    self._debounce_timer = nil

    self.display_entries = build_display_entries(self.entries, self.filter, self.query)
    self.visible_rows = build_visible_rows(self.display_entries, self.expanded_filepath, self.expanded_issues)
    return self
end

--- Is the Neovim window still alive?
---@return boolean
function Window:is_valid()
    return self.win_id ~= nil and vim.api.nvim_win_is_valid(self.win_id)
end

--- Floating-window geometry
---@return table
function Window:make_win_opts()
    return float.make_win_opts({
        width_ratio = 0.8,
        height_ratio = 0.5,
        title = "Huginn Home",
        content_count = #self.visible_rows,
        content_offset = 5,
    })
end

--- Render the buffer contents
function Window:render()
    if not self.buf_id or not vim.api.nvim_buf_is_valid(self.buf_id) then return end
    if not self:is_valid() then return end

    local win_width = vim.api.nvim_win_get_width(self.win_id)

    -- Header
    local title = "HuginnHome"
    local filter_label = "[Filter: " .. issue_filter.FILTER_LABELS[self.filter] .. "]"
    local padding = math.max(win_width - #title - #filter_label, 1)
    local header = title .. string.rep(" ", padding) .. filter_label

    -- Separator
    local separator = string.rep("\xe2\x94\x80", win_width)

    local lines = { header, separator }
    self.line_map = {}

    if #self.visible_rows == 0 then
        local msg = "(no files match)"
        local pad = math.max(math.floor((win_width - #msg) / 2), 0)
        table.insert(lines, string.rep(" ", pad) .. msg)
    else
        for i, row in ipairs(self.visible_rows) do
            if row.type == "file" then
                table.insert(lines, row.filepath .. "  (" .. row.count .. ")")
            else
                local line = "  " .. row.description
                if row.reference then
                    line = line .. "  (" .. row.reference .. ")"
                end
                table.insert(lines, line)
            end
            self.line_map[#lines] = self.visible_rows[i]
        end
    end

    -- Footer
    table.insert(lines, separator)
    local help_pad = math.max(math.floor((win_width - #HELP_TEXT) / 2), 0)
    table.insert(lines, string.rep(" ", help_pad) .. HELP_TEXT)

    -- Input line
    table.insert(lines, "> " .. self.query)

    vim.api.nvim_buf_set_lines(self.buf_id, 0, -1, false, lines)

    -- Resize window
    vim.api.nvim_win_set_config(self.win_id, self:make_win_opts())

    -- Place cursor on input line at end of text
    local last_line = vim.api.nvim_buf_line_count(self.buf_id)
    local input_text = "> " .. self.query
    vim.api.nvim_win_set_cursor(self.win_id, { last_line, #input_text })

    self:apply_selection_highlight()
end

--- Highlight the selected row using extmark
function Window:apply_selection_highlight()
    if not self.buf_id or not vim.api.nvim_buf_is_valid(self.buf_id) then return end
    vim.api.nvim_buf_clear_namespace(self.buf_id, self.ns_id, 0, -1)

    if #self.visible_rows == 0 then return end

    -- visible_rows[1] maps to buffer line 3 (0-based line 2), so:
    -- buffer line (0-based) = selected_index - 1 + 2 = selected_index + 1
    local buf_line = self.selected_index + 1
    vim.api.nvim_buf_add_highlight(self.buf_id, self.ns_id, "CursorLine", buf_line, 0, -1)
end

--- Move the selection by delta with wraparound
---@param delta integer
function Window:move_selection(delta)
    if #self.visible_rows == 0 then return end

    self.selected_index = self.selected_index + delta
    if self.selected_index < 1 then
        self.selected_index = #self.visible_rows
    elseif self.selected_index > #self.visible_rows then
        self.selected_index = 1
    end

    self:update_expansion()
    self:apply_selection_highlight()
end

--- Auto-expand the file at the current selection (accordion)
function Window:update_expansion()
    if #self.visible_rows == 0 then return end

    local row = self.visible_rows[self.selected_index]
    if not row then return end

    local target_filepath = row.filepath

    if self.expanded_filepath == target_filepath then return end

    local entry = self.entries[target_filepath]
    if not entry then return end

    self.expanded_issues = self:load_expanded_issues(target_filepath, entry, self.filter, self.context)
    self.expanded_filepath = target_filepath

    self.visible_rows = build_visible_rows(self.display_entries, self.expanded_filepath, self.expanded_issues)

    -- Find the same row in the new visible_rows
    for i, r in ipairs(self.visible_rows) do
        if row.type == "file" and r.type == "file" and r.filepath == row.filepath then
            self.selected_index = i
            break
        elseif row.type == "issue" and r.type == "issue" and r.issue_id == row.issue_id then
            self.selected_index = i
            break
        end
    end

    self:render()
end

--- Load full issue data for an expanded file
---@param fp string filepath
---@param entry huginn.IndexEntry
---@param filter string
---@param ctx huginn.CommandContext
---@return table[] list of { id, description, reference }
function Window:load_expanded_issues(fp, entry, filter, ctx)
    local ids = {}
    for id, status in pairs(entry.issues) do
        if filter == "all" or status == filter then
            table.insert(ids, id)
        end
    end
    table.sort(ids)

    local result = {}
    for _, id in ipairs(ids) do
        local iss, err = issue_mod.read(id)
        if err then
            ctx.logger:alert("WARN", "Failed to read issue " .. id .. ": " .. err)
            return {}
        end
        if iss then
            local ref = nil
            if iss.location and iss.location.reference and #iss.location.reference > 0 then
                local ref_str = iss.location.reference[1]
                local pipe = ref_str:find("|", 1, true)
                if pipe then
                    ref = ref_str:sub(1, pipe - 1) .. ":" .. ref_str:sub(pipe + 1)
                end
            end
            table.insert(result, {
                id = id,
                description = issue_mod.get_ui_description(ctx, iss),
                reference = ref,
            })
        end
    end
    return result
end

--- Cycle the filter and re-render
function Window:cycle_filter()
    self.filter = issue_filter.next(self.filter)
    self.expanded_filepath = nil
    self.expanded_issues = {}
    self.display_entries = build_display_entries(self.entries, self.filter, self.query)
    self.visible_rows = build_visible_rows(self.display_entries, self.expanded_filepath, self.expanded_issues)
    self.selected_index = 1
    self:update_expansion()
    self:render()
end

--- Stop and release the debounce timer if active
function Window:_cancel_debounce()
    if self._debounce_timer then
        self._debounce_timer:stop()
        self._debounce_timer:close()
        self._debounce_timer = nil
    end
end

--- Cancel any pending debounce and fire immediately
function Window:flush_debounce()
    if self._debounce_timer then
        self:_cancel_debounce()
        self:on_input_changed()
    end
end

--- Handle input line text change
function Window:on_input_changed()
    if not self.buf_id or not vim.api.nvim_buf_is_valid(self.buf_id) then return end

    local last_line = vim.api.nvim_buf_line_count(self.buf_id)
    local input_line = vim.api.nvim_buf_get_lines(self.buf_id, last_line - 1, last_line, false)[1] or ""

    -- Strip "> " prefix; if user backspaced into the prefix, treat as empty
    local new_query
    if input_line:sub(1, 2) == "> " then
        new_query = input_line:sub(3)
    else
        new_query = ""
    end

    -- If the query hasn't changed (e.g. render() wrote back the same text), bail out
    -- so we don't reset selected_index on a programmatic buffer update.
    if new_query == self.query then return end

    self.query = new_query
    self.expanded_filepath = nil
    self.expanded_issues = {}
    self.display_entries = build_display_entries(self.entries, self.filter, self.query)
    self.visible_rows = build_visible_rows(self.display_entries, self.expanded_filepath, self.expanded_issues)
    self.selected_index = 1
    self:update_expansion()
    self:render()
    self:apply_selection_highlight()
end

--- Handle Enter key: open file or navigate to issue
function Window:on_enter()
    self:flush_debounce()
    if #self.visible_rows == 0 then return end

    local row = self.visible_rows[self.selected_index]
    if not row then return end

    M.close()

    if row.type == "file" then
        local abs_path = filepath.join(self.context.cwd, row.filepath)
        vim.cmd("edit " .. vim.fn.fnameescape(abs_path))
    elseif row.type == "issue" then
        local abs_path = filepath.join(self.context.cwd, row.filepath)
        vim.cmd("edit " .. vim.fn.fnameescape(abs_path))

        local iss = issue_mod.read(row.issue_id)
        if not iss or not iss.location then return end

        local results = location.resolve(self.context.cwd, iss.location)
        if not results then return end

        for _, ref in ipairs(iss.location.reference) do
            local r = results[ref]
            if r and r.result == "found" and r.node then
                local start_row, start_col = r.node:range()
                vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
                break
            end
        end
    end
end

--- Create the buffer, window, and wire up keymaps/autocmds
function Window:activate()
    -- Buffer
    self.buf_id = float.create_buf()

    -- Window
    local ok_win, wid = pcall(vim.api.nvim_open_win, self.buf_id, true, self:make_win_opts())
    if not ok_win then
        self.buf_id = nil
        return
    end
    self.win_id = wid
    vim.api.nvim_set_option_value("cursorline", false, { win = self.win_id })
    vim.api.nvim_set_option_value("number", false, { win = self.win_id })
    vim.api.nvim_set_option_value("relativenumber", false, { win = self.win_id })

    -- Initial expansion of first file
    self:update_expansion()
    self:render()

    vim.cmd("startinsert")

    self:bind_keys()
    self:bind_autocmds()
end

--- Destroy the window and wipe autocmds
function Window:deactivate()
    self:_cancel_debounce()
    if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
        vim.api.nvim_win_close(self.win_id, true)
    end
    pcall(vim.api.nvim_del_augroup_by_name, AUGROUP_NAME)
    vim.cmd("stopinsert")
    self.win_id = nil
    self.buf_id = nil
end

--- Register buffer-local keymaps
function Window:bind_keys()
    local buf = self.buf_id
    if not buf then return end

    -- Close
    vim.keymap.set("n", "q", function() M.close() end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<Esc>", function() M.close() end, { buffer = buf, nowait = true })

    -- Enter
    vim.keymap.set("i", "<CR>", function() self:on_enter() end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<CR>", function() self:on_enter() end, { buffer = buf, nowait = true })

    -- Filter
    vim.keymap.set("i", "<C-f>", function() self:cycle_filter() end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<C-f>", function() self:cycle_filter() end, { buffer = buf, nowait = true })

    -- Navigation
    vim.keymap.set("i", "<C-n>", function() self:move_selection(1) end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<C-n>", function() self:move_selection(1) end, { buffer = buf, nowait = true })
    vim.keymap.set("i", "<Down>", function() self:move_selection(1) end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<Down>", function() self:move_selection(1) end, { buffer = buf, nowait = true })
    vim.keymap.set("i", "<C-p>", function() self:move_selection(-1) end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<C-p>", function() self:move_selection(-1) end, { buffer = buf, nowait = true })
    vim.keymap.set("i", "<Up>", function() self:move_selection(-1) end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<Up>", function() self:move_selection(-1) end, { buffer = buf, nowait = true })
end

--- Register autocmds
function Window:bind_autocmds()
    local group = vim.api.nvim_create_augroup(AUGROUP_NAME, { clear = true })

    float.on_win_closed(group, self.win_id, AUGROUP_NAME, function()
        self.win_id = nil
        self.buf_id = nil
    end)

    float.on_vim_resized(group, function() return self.win_id end, function()
        return self:make_win_opts()
    end)

    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = group,
        buffer = self.buf_id,
        callback = function()
            if not self:is_valid() then return end
            local last_line = vim.api.nvim_buf_line_count(self.buf_id)
            local cursor = vim.api.nvim_win_get_cursor(self.win_id)
            if cursor[1] ~= last_line then
                local input_text = "> " .. self.query
                vim.api.nvim_win_set_cursor(self.win_id, { last_line, #input_text })
            end
        end,
    })

    vim.api.nvim_create_autocmd("TextChangedI", {
        group = group,
        buffer = self.buf_id,
        callback = function()
            self:_cancel_debounce()
            self._debounce_timer = vim.uv.new_timer()
            self._debounce_timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(function()
                self:_cancel_debounce()
                self:on_input_changed()
            end))
        end,
    })

    float.on_win_leave(group, self.buf_id, function() return self.win_id end)
end

-- ── Module-level API ────────────────────────────────────────────────

---@type huginn.HomeWindow|nil
local active_window = nil

--- Open the home window
---@param opts table { entries, context }
function M.open(opts)
    if active_window and active_window:is_valid() then
        vim.api.nvim_set_current_win(active_window.win_id)
        return
    end

    if active_window then
        active_window:deactivate()
    end

    active_window = Window.new(opts)
    active_window:activate()
end

--- Close the active home window
function M.close()
    if active_window then
        active_window:deactivate()
        active_window = nil
    end
end

--- Check whether the home window is currently open
---@return boolean
function M.is_open()
    return active_window ~= nil and active_window:is_valid()
end

--- Close and reset (testing escape hatch)
function M._close()
    M.close()
end

--- Get the active Window instance (testing only)
---@return huginn.HomeWindow|nil
function M._get_window()
    return active_window
end

return M
