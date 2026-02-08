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

-- annotation.lua
-- Read-only view layer: renders virtual text markers on buffer lines with associated Huginn issues


local context = require("huginn.modules.context")
local issue_index = require("huginn.modules.issue_index")
local issue = require("huginn.modules.issue")
local location = require("huginn.modules.location")
local filepath = require("huginn.modules.filepath")

local M = {}

local ICON = "\xf0\x9f\x90\xa6\xe2\x80\x8d\xe2\xac\x9b"
local DAGGER = "\xe2\x80\xa0"

local ns = nil
local hl_group = "HuginnAnnotation"

--- Per-buffer annotation cache: bufnr -> {tick, fingerprint, open_lines, closed_lines}
local line_cache = {}

--- Debounce timer for TextChanged re-annotation
local debounce_timer = nil

--- Cancel and release the debounce timer if active
local function cancel_debounce()
    if debounce_timer then
        debounce_timer:stop()
        debounce_timer:close()
        debounce_timer = nil
    end
end

--- Compute a fingerprint string from an index entry's issue map
---@param entry table? index entry with .issues field
---@return string fingerprint sorted "id=status;..." string
local function issue_fingerprint(entry)
    if not entry then return "" end
    local parts = {}
    for id, status in pairs(entry.issues) do
        parts[#parts + 1] = id .. "=" .. status
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

--- Resolve issue locations and aggregate counts by 0-indexed line
---@param ids string[] issue IDs to resolve
---@param cwd string project root
---@return table<integer, integer> line -> count of issues on that line
local function resolve_lines(ids, cwd)
    local line_counts = {}
    local seen_per_line = {}

    for _, id in ipairs(ids) do
        local iss = issue.read(id)
        if iss and iss.location and #iss.location.reference > 0 then
            local results = location.resolve(cwd, iss.location)
            if results then
                for _, res in pairs(results) do
                    if res.result == "found" and res.node then
                        local start_row = res.node:range()
                        if not seen_per_line[id] then
                            seen_per_line[id] = {}
                        end
                        if not seen_per_line[id][start_row] then
                            seen_per_line[id][start_row] = true
                            line_counts[start_row] = (line_counts[start_row] or 0) + 1
                        end
                    end
                end
                -- Scoped issues with unresolvable references are intentionally
                -- omitted: the annotation reappears when the code returns.
            else
                line_counts[0] = (line_counts[0] or 0) + 1
            end
        else
            line_counts[0] = (line_counts[0] or 0) + 1
        end
    end

    return line_counts
end

--- Place extmarks on a buffer for resolved line counts
---@param bufnr integer buffer number
---@param open_lines table<integer, integer> line -> open issue count
---@param closed_lines table<integer, integer> line -> closed issue count
local function place_extmarks(bufnr, open_lines, closed_lines)
    for line, count in pairs(open_lines) do
        vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
            virt_text = { { ICON .. "(" .. count .. ")", hl_group } },
            virt_text_pos = "eol",
        })
    end

    for line, _ in pairs(closed_lines) do
        if not open_lines[line] then
            vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
                virt_text = { { ICON .. "[" .. DAGGER .. "]", hl_group } },
                virt_text_pos = "eol",
            })
        end
    end
end

--- Compute and display annotations for a buffer
---@param bufnr integer buffer number
function M.annotate(bufnr)
    local ctx = context.get()
    if not ctx then return end

    if not (ctx.config.annotation and ctx.config.annotation.enabled) then
        return
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then return end

    local buf_path = vim.api.nvim_buf_get_name(bufnr)
    if not buf_path or buf_path == "" then return end

    local rel_path = filepath.absolute_to_relative(buf_path, ctx.cwd)
    if not rel_path then return end

    local entry = issue_index.get(rel_path)
    if not entry then
        M.clear(bufnr)
        return
    end

    local tick = vim.api.nvim_buf_get_changedtick(bufnr)
    local fp = issue_fingerprint(entry)
    local cached = line_cache[bufnr]
    if cached and cached.tick == tick and cached.fingerprint == fp then
        return
    end

    local open_ids = {}
    local closed_ids = {}

    for id, status in pairs(entry.issues) do
        if status == "open" then
            table.insert(open_ids, id)
        elseif status == "closed" then
            table.insert(closed_ids, id)
        end
    end

    M.clear(bufnr)

    if #open_ids == 0 and #closed_ids == 0 then
        return
    end

    local open_lines = resolve_lines(open_ids, ctx.cwd)
    local closed_lines = resolve_lines(closed_ids, ctx.cwd)
    place_extmarks(bufnr, open_lines, closed_lines)

    line_cache[bufnr] = {
        tick = tick,
        fingerprint = fp,
        open_lines = open_lines,
        closed_lines = closed_lines,
    }
end

--- Clear all huginn extmarks from a buffer
---@param bufnr integer buffer number
function M.clear(bufnr)
    if not ns then return end
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    line_cache[bufnr] = nil
end

--- Register namespace, highlight, autocmds, and config listener
function M.setup()
    ns = vim.api.nvim_create_namespace("huginn_annotation")

    local ctx = context.get()
    local bg = "#ffffff"
    local fg = "#000000"
    if ctx and ctx.config.annotation then
        if ctx.config.annotation.background then
            bg = ctx.config.annotation.background
        end
        if ctx.config.annotation.foreground then
            fg = ctx.config.annotation.foreground
        end
    end
    vim.api.nvim_set_hl(0, hl_group, { bg = bg, fg = fg })

    local group = vim.api.nvim_create_augroup("HuginnAnnotation", { clear = true })

    vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
        group = group,
        callback = function(args)
            M.annotate(args.buf)
        end,
    })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = group,
        callback = function(args)
            cancel_debounce()
            local ctx = context.get()
            local delay = 300
            if ctx and ctx.config.annotation and ctx.config.annotation.debounce then
                delay = ctx.config.annotation.debounce
            end
            local bufnr = args.buf
            debounce_timer = vim.uv.new_timer()
            debounce_timer:start(delay, 0, vim.schedule_wrap(function()
                cancel_debounce()
                M.annotate(bufnr)
            end))
        end,
    })

    context.on_config_change(function(new_config)
        local new_bg = "#ffffff"
        local new_fg = "#000000"
        if new_config.annotation then
            if new_config.annotation.background then
                new_bg = new_config.annotation.background
            end
            if new_config.annotation.foreground then
                new_fg = new_config.annotation.foreground
            end
        end
        vim.api.nvim_set_hl(0, hl_group, { bg = new_bg, fg = new_fg })
        M.refresh()
    end)
end

--- Re-annotate the current buffer
function M.refresh()
    local bufnr = vim.api.nvim_get_current_buf()
    M.annotate(bufnr)
end

--- Reset module state (testing only)
function M._reset()
    cancel_debounce()
    if ns then
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(bufnr) then
                pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns, 0, -1)
            end
        end
    end
    ns = nil
    line_cache = {}
    vim.api.nvim_create_augroup("HuginnAnnotation", { clear = true })
end

--- Expose namespace for testing
function M._get_ns()
    return ns
end

return M
