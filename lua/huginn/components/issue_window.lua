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

-- issue_window.lua
-- Floating editor window for modifying issue content


local issue_mod = require("huginn.modules.issue")
local context = require("huginn.modules.context")
local confirm = require("huginn.components.confirm")
local float = require("huginn.components.float")

local M = {}

local RESERVED_LABELS = { Version = true, Status = true, Location = true }
local AUGROUP_NAME = "HuginnIssueWindow"
local HELP_TEXT_WITH_BACK = " C-s save  Esc back  C-q close  C-g open file  C-y yank id "
local HELP_TEXT_DEFAULT = " C-s save  Esc close  C-g open file  C-y yank id "

--- Get logger from context if available
---@return huginn.Logger?
local function get_logger()
    local ctx = context.get()
    return ctx and ctx.logger or nil
end

-- ──────────────────────────────────────────────────────────────────────
-- State
-- ──────────────────────────────────────────────────────────────────────

---@type integer|nil
local win_id = nil

---@type integer|nil
local buf_id = nil

---@type string|nil
local issue_id = nil

---@type function|nil  callback when user dismisses back (Esc)
local on_dismiss = nil

---@type function|nil  callback when user quits to vim (C-q / C-g)
local on_quit = nil

-- ──────────────────────────────────────────────────────────────────────
-- Window geometry
-- ──────────────────────────────────────────────────────────────────────

--- Compute centered floating window dimensions
---@param title string window title text
---@return table config for nvim_open_win
local function make_win_opts(title)
    return float.make_win_opts({
        width_ratio = 0.6,
        height_ratio = 0.7,
        title = title,
        footer = { { on_dismiss and HELP_TEXT_WITH_BACK or HELP_TEXT_DEFAULT, "Comment" } },
        footer_pos = "center",
    })
end

-- ──────────────────────────────────────────────────────────────────────
-- Block rendering: issue.blocks -> buffer lines
-- ──────────────────────────────────────────────────────────────────────

--- Render issue blocks into buffer lines.
--- Order: Issue Description (if present), custom blocks alphabetically,
--- Issue Resolution (if present) last.
---@param blocks table<string, string>
---@return string[]
local function blocks_to_lines(blocks)
    local ordered_labels = {}
    local seen = {}

    -- Issue Description first
    if blocks["Issue Description"] then
        table.insert(ordered_labels, "Issue Description")
        seen["Issue Description"] = true
    end

    -- Custom blocks alphabetically
    local custom = {}
    for label, _ in pairs(blocks) do
        if not seen[label] and label ~= "Issue Resolution" then
            table.insert(custom, label)
        end
    end
    table.sort(custom)
    for _, label in ipairs(custom) do
        table.insert(ordered_labels, label)
        seen[label] = true
    end

    -- Issue Resolution last
    if blocks["Issue Resolution"] then
        table.insert(ordered_labels, "Issue Resolution")
    end

    local lines = {}
    for i, label in ipairs(ordered_labels) do
        if i > 1 then
            table.insert(lines, "")
        end
        table.insert(lines, "## " .. label)
        local content = blocks[label]
        if content and content ~= "" then
            for _, line in ipairs(vim.split(content, "\n")) do
                table.insert(lines, line)
            end
        end
    end

    return lines
end

-- ──────────────────────────────────────────────────────────────────────
-- Buffer parsing: buffer lines -> blocks map
-- ──────────────────────────────────────────────────────────────────────

--- Strip leading and trailing blank lines from an array of strings
---@param lines string[]
---@return string trimmed content joined with newlines
local function trim_block_content(lines)
    local start_idx = 1
    while start_idx <= #lines and lines[start_idx]:match("^%s*$") do
        start_idx = start_idx + 1
    end

    local end_idx = #lines
    while end_idx >= start_idx and lines[end_idx]:match("^%s*$") do
        end_idx = end_idx - 1
    end

    if start_idx > end_idx then
        return ""
    end

    local result = {}
    for i = start_idx, end_idx do
        table.insert(result, lines[i])
    end
    return table.concat(result, "\n")
end

--- Parse buffer lines into a blocks map.
--- Content before the first ## header is discarded.
--- Reserved labels are discarded with a warning.
---@param buf_lines string[]
---@return table<string, string> blocks
local function parse_blocks(buf_lines)
    local logger = get_logger()
    local blocks = {}
    local current_label = nil
    local current_lines = {}

    local function save_block()
        if current_label then
            local label_trimmed = vim.trim(current_label)
            if label_trimmed == "" then
                -- Empty label: ignore
            elseif RESERVED_LABELS[label_trimmed] then
                if logger then
                    logger:log("WARN", "Reserved label '" .. label_trimmed .. "' in issue window buffer; discarding")
                end
            else
                blocks[label_trimmed] = trim_block_content(current_lines)
            end
        end
    end

    for _, line in ipairs(buf_lines) do
        local h2 = line:match("^## (.+)$")
        if h2 then
            save_block()
            current_label = h2
            current_lines = {}
        elseif current_label then
            table.insert(current_lines, line)
        end
        -- Content before the first ## is discarded (current_label is nil)
    end
    save_block()

    return blocks
end

-- ──────────────────────────────────────────────────────────────────────
-- Save logic
-- ──────────────────────────────────────────────────────────────────────

--- Save buffer content back to the issue file.
--- Returns true on success, false on failure.
---@return boolean success
local function save()
    local logger = get_logger()

    if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
        return false
    end

    local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
    local blocks = parse_blocks(lines)

    -- Read latest issue state (picks up external changes to hidden fields)
    local iss, read_err = issue_mod.read(issue_id)
    if not iss then
        if logger then
            logger:alert("ERROR", "Failed to read issue: " .. (read_err or "unknown"))
        end
        -- Close the window — issue was deleted externally
        M.close()
        return false
    end

    -- Replace blocks
    iss.blocks = blocks

    local ok, write_err = issue_mod.write(iss)
    if not ok then
        if logger then
            logger:alert("ERROR", "Failed to write issue: " .. (write_err or "unknown"))
        end
        -- Keep window open so user does not lose work
        return false
    end

    return true
end

-- ──────────────────────────────────────────────────────────────────────
-- Keybinding handlers
-- ──────────────────────────────────────────────────────────────────────

--- Save and close (<C-s>)
--- When opened from show window, returns there after saving.
local function handle_save()
    vim.cmd("stopinsert")
    if save() then
        local cb = on_dismiss
        M.close()
        if cb then cb() end
    end
end

--- Open raw Issue.md (<C-g>)
local function handle_open_raw()
    vim.cmd("stopinsert")
    local logger = get_logger()

    local function do_open()
        local path, path_err = issue_mod.issue_path(issue_id)
        if not path then
            if logger then
                logger:alert("ERROR", "Failed to resolve issue path: " .. (path_err or "unknown"))
            end
            return
        end
        local cb = on_quit
        M.close()
        if cb then cb() end
        vim.cmd("edit " .. vim.fn.fnameescape(path))
    end

    if buf_id and vim.api.nvim_buf_is_valid(buf_id) and vim.bo[buf_id].modified then
        confirm.show({
            message = "Discard unsaved changes?",
            level = "caution",
        }, function(confirmed)
            if confirmed then
                do_open()
            end
        end)
    else
        do_open()
    end
end

--- Yank issue ID (<C-y>)
local function handle_yank_id()
    vim.cmd("stopinsert")
    if issue_id then
        vim.fn.setreg('"', issue_id)
        vim.api.nvim_echo({ { "[Huginn] " .. issue_id, "Normal" } }, true, {})
    end
end

--- Dismiss (<Esc>)
--- When opened from show window, returns there. Otherwise closes.
local function handle_dismiss()
    local function do_dismiss()
        local cb = on_dismiss
        M.close()
        if cb then cb() end
    end

    if buf_id and vim.api.nvim_buf_is_valid(buf_id) and vim.bo[buf_id].modified then
        confirm.show({
            message = "Discard unsaved changes?",
            level = "caution",
        }, function(confirmed)
            if confirmed then
                do_dismiss()
            end
        end)
    else
        do_dismiss()
    end
end

--- Quit directly to vim (<C-q>)
--- Always closes without returning to show window.
local function handle_quit()
    vim.cmd("stopinsert")
    local function do_quit()
        local cb = on_quit
        M.close()
        if cb then cb() end
    end

    if buf_id and vim.api.nvim_buf_is_valid(buf_id) and vim.bo[buf_id].modified then
        confirm.show({
            message = "Discard unsaved changes?",
            level = "caution",
        }, function(confirmed)
            if confirmed then
                do_quit()
            end
        end)
    else
        do_quit()
    end
end

-- ──────────────────────────────────────────────────────────────────────
-- Keymaps and autocmds
-- ──────────────────────────────────────────────────────────────────────

--- Register buffer-local keymaps
---@param buf integer buffer handle
local function bind_keys(buf)
    vim.keymap.set({ "n", "i" }, "<C-s>", handle_save, { buffer = buf, nowait = true })
    vim.keymap.set({ "n", "i" }, "<C-g>", handle_open_raw, { buffer = buf, nowait = true })
    vim.keymap.set({ "n", "i" }, "<C-y>", handle_yank_id, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<Esc>", handle_dismiss, { buffer = buf, nowait = true })
    vim.keymap.set({ "n", "i" }, "<C-q>", handle_quit, { buffer = buf, nowait = true })
end

--- Register autocmds
---@param win integer window handle
local function bind_autocmds(win)
    local group = vim.api.nvim_create_augroup(AUGROUP_NAME, { clear = true })
    local win_id_fn = function() return win_id end

    float.on_vim_resized(group, win_id_fn, function()
        local iss = issue_mod.read(issue_id)
        local title = issue_id .. " [" .. (iss and iss.status or "?") .. "]"
        return make_win_opts(title)
    end)

    float.on_win_closed(group, win, AUGROUP_NAME, function()
        win_id = nil
        buf_id = nil
        issue_id = nil
    end)

    float.on_win_leave(group, buf_id, win_id_fn)
end

-- ──────────────────────────────────────────────────────────────────────
-- Public API
-- ──────────────────────────────────────────────────────────────────────

--- Open the floating editor window for the given issue ID.
--- Reads the issue to get the latest state, then populates the buffer
--- with user-facing blocks.
---@param id string issue ID
---@param opts? { on_dismiss?: function, on_quit?: function }
function M.open(id, opts)
    opts = opts or {}
    local logger = get_logger()

    -- If already open, focus the existing window
    if M.is_open() then
        vim.api.nvim_set_current_win(win_id)
        return
    end

    -- Read issue
    local iss, err = issue_mod.read(id)
    if not iss then
        if logger then
            logger:alert("ERROR", "Failed to read issue: " .. (err or "unknown"))
        end
        return
    end

    issue_id = id
    on_dismiss = opts.on_dismiss
    on_quit = opts.on_quit

    -- Build title
    local title = id .. " [" .. iss.status .. "]"

    -- Create buffer
    buf_id = float.create_buf("markdown")

    -- Populate buffer
    local lines = blocks_to_lines(iss.blocks)
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

    -- Mark buffer as unmodified
    vim.api.nvim_set_option_value("modified", false, { buf = buf_id })

    -- Open window
    local ok_win, wid = pcall(vim.api.nvim_open_win, buf_id, true, make_win_opts(title))
    if not ok_win then
        buf_id = nil
        issue_id = nil
        on_dismiss = nil
        on_quit = nil
        return
    end
    win_id = wid
    vim.api.nvim_set_option_value("number", false, { win = win_id })
    vim.api.nvim_set_option_value("relativenumber", false, { win = win_id })
    vim.api.nvim_set_option_value("wrap", true, { win = win_id })
    vim.api.nvim_set_option_value("linebreak", true, { win = win_id })

    bind_keys(buf_id)
    bind_autocmds(win_id)
end

--- Close the floating window and clean up state.
--- Does not check for unsaved changes.
function M.close()
    if win_id and vim.api.nvim_win_is_valid(win_id) then
        vim.api.nvim_win_close(win_id, true)
    end
    pcall(vim.api.nvim_del_augroup_by_name, AUGROUP_NAME)
    win_id = nil
    buf_id = nil
    issue_id = nil
    on_dismiss = nil
    on_quit = nil
end

--- Check whether the issue window is currently open and valid.
---@return boolean
function M.is_open()
    return win_id ~= nil and vim.api.nvim_win_is_valid(win_id)
end

--- Close and reset (testing escape hatch)
function M._close()
    M.close()
end

--- Get state for testing
---@return table|nil
function M._get_state()
    if not win_id then return nil end
    return {
        win_id = win_id,
        buf_id = buf_id,
        issue_id = issue_id,
    }
end

--- Exposed for testing
M._parse_blocks = parse_blocks
M._blocks_to_lines = blocks_to_lines

return M
