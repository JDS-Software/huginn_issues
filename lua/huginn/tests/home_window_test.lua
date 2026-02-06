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

-- home_window_test.lua
-- Tests for the home_window floating window component

local M = {}

local home_window = require("huginn.components.home_window")
local issue_index = require("huginn.modules.issue_index")

local IndexEntry = issue_index._IndexEntry

--- Build a minimal IndexEntry for testing
---@param fp string filepath
---@param issues table<string, string> map of issue_id -> status
---@return huginn.IndexEntry
local function make_entry(fp, issues)
    local entry = IndexEntry.new(fp)
    for id, status in pairs(issues) do
        entry.issues[id] = status
    end
    entry.dirty = false
    return entry
end

--- Build default entries map for testing
---@return table<string, huginn.IndexEntry>
local function make_entries()
    return {
        ["src/main.lua"] = make_entry("src/main.lua", {
            ["20260110_140000"] = "open",
            ["20260110_150000"] = "closed",
        }),
        ["src/utils.lua"] = make_entry("src/utils.lua", {
            ["20260110_160000"] = "open",
        }),
    }
end

--- Build default opts for home_window.open
---@param entries table<string, huginn.IndexEntry>?
---@return table
local function make_opts(entries)
    return {
        entries = entries or make_entries(),
        context = {
            cwd = "/tmp/test_project",
            config = { show = { description_length = 80 } },
            logger = { alert = function() end },
        },
    }
end

local function test_open_creates_floating_window()
    home_window.open(make_opts())
    assert_true(home_window.is_open(), "home window should be open after open()")

    home_window._close()
end

local function test_open_enforces_singleton()
    home_window.open(make_opts())
    assert_true(home_window.is_open(), "home window should be open after first open()")

    home_window.open(make_opts())
    assert_true(home_window.is_open(), "home window should still be open after second open()")

    home_window._close()
end

local function test_close_cleans_up_state()
    home_window.open(make_opts())
    assert_true(home_window.is_open(), "home window should be open")

    home_window._close()
    assert_false(home_window.is_open(), "home window should be closed after _close()")

    -- Should be able to reopen
    home_window.open(make_opts())
    assert_true(home_window.is_open(), "home window should be open after reopen")

    home_window._close()
end

local function test_filter_cycling()
    home_window.open(make_opts())

    local win = home_window._get_window()
    assert_not_nil(win, "active window should exist")
    assert_equal("all", win.filter, "initial filter should be 'all'")
    assert_equal(2, #win.display_entries, "all filter should show 2 files")

    -- Cycle to open
    win:cycle_filter()
    assert_equal("open", win.filter, "filter should cycle to 'open'")
    assert_equal(2, #win.display_entries, "open filter should show 2 files (both have open issues)")

    -- Cycle to closed
    win:cycle_filter()
    assert_equal("closed", win.filter, "filter should cycle to 'closed'")
    assert_equal(1, #win.display_entries, "closed filter should show 1 file (only main.lua has closed)")

    -- Cycle back to all
    win:cycle_filter()
    assert_equal("all", win.filter, "filter should cycle back to 'all'")
    assert_equal(2, #win.display_entries, "all filter should show 2 files again")

    home_window._close()
end

local function test_render_formats_lines()
    home_window.open(make_opts())

    local win = home_window._get_window()
    assert_not_nil(win, "active window should exist")
    assert_not_nil(win.buf_id, "buffer should exist")

    local lines = vim.api.nvim_buf_get_lines(win.buf_id, 0, -1, false)

    -- Line 1: header with title and filter label
    assert_match("HuginnHome", lines[1], "header should contain title")
    assert_match("%[Filter: ALL%]", lines[1], "header should contain filter label")

    -- Line 2: separator
    assert_true(lines[2]:find("\xe2\x94\x80") == 1, "line 2 should start with separator character")

    -- File entry lines (sorted alphabetically)
    assert_match("src/main.lua", lines[3], "first entry should be main.lua (alphabetical)")
    assert_match("%(2%)", lines[3], "main.lua should show count 2")

    -- Footer separator + help + input line
    local line_count = #lines
    assert_match("^> ", lines[line_count], "last line should be the input prompt")
    assert_match("C%-f filter", lines[line_count - 1], "second-to-last should show help text")

    home_window._close()
end

local function test_display_entries_sorted_alphabetically()
    local entries = {
        ["z/last.lua"] = make_entry("z/last.lua", { ["20260110_140000"] = "open" }),
        ["a/first.lua"] = make_entry("a/first.lua", { ["20260110_150000"] = "open" }),
        ["m/middle.lua"] = make_entry("m/middle.lua", { ["20260110_160000"] = "open" }),
    }
    home_window.open(make_opts(entries))

    local win = home_window._get_window()
    assert_not_nil(win, "active window should exist")
    assert_equal(3, #win.display_entries, "should have 3 display entries")
    assert_equal("a/first.lua", win.display_entries[1].filepath, "first entry should be a/first.lua")
    assert_equal("m/middle.lua", win.display_entries[2].filepath, "second entry should be m/middle.lua")
    assert_equal("z/last.lua", win.display_entries[3].filepath, "third entry should be z/last.lua")

    home_window._close()
end

local function test_selection_navigation()
    home_window.open(make_opts())

    local win = home_window._get_window()
    assert_not_nil(win, "active window should exist")
    assert_equal(1, win.selected_index, "initial selection should be 1")

    -- Move down
    win:move_selection(1)
    -- After moving down from file row 1 (src/main.lua), we may land on an expanded issue row
    -- or on the next file row depending on expansion state.
    assert_true(win.selected_index > 1, "selection should move down")

    -- Move up should go back
    local prev = win.selected_index
    win:move_selection(-1)
    assert_true(win.selected_index < prev, "selection should move up")

    home_window._close()
end

local function test_selection_wraparound()
    local entries = {
        ["src/a.lua"] = make_entry("src/a.lua", { ["20260110_140000"] = "open" }),
    }
    home_window.open(make_opts(entries))

    local win = home_window._get_window()
    assert_not_nil(win, "active window should exist")

    -- Move up from first item should wrap to last
    win:move_selection(-1)
    assert_equal(#win.visible_rows, win.selected_index, "should wrap to last row")

    -- Move down from last item should wrap to first
    win:move_selection(1)
    assert_equal(1, win.selected_index, "should wrap to first row")

    home_window._close()
end

local function test_filter_hides_zero_count_files()
    local entries = {
        ["src/open_only.lua"] = make_entry("src/open_only.lua", { ["20260110_140000"] = "open" }),
        ["src/closed_only.lua"] = make_entry("src/closed_only.lua", { ["20260110_150000"] = "closed" }),
    }
    home_window.open(make_opts(entries))

    local win = home_window._get_window()
    assert_not_nil(win, "active window should exist")

    -- Cycle to "open" — closed_only.lua should be hidden
    win:cycle_filter()
    assert_equal("open", win.filter)
    assert_equal(1, #win.display_entries, "open filter should hide closed-only file")
    assert_equal("src/open_only.lua", win.display_entries[1].filepath)

    -- Cycle to "closed" — open_only.lua should be hidden
    win:cycle_filter()
    assert_equal("closed", win.filter)
    assert_equal(1, #win.display_entries, "closed filter should hide open-only file")
    assert_equal("src/closed_only.lua", win.display_entries[1].filepath)

    home_window._close()
end

local function test_no_entries_shows_placeholder()
    local entries = {}
    home_window.open(make_opts(entries))

    local win = home_window._get_window()
    assert_not_nil(win, "active window should exist")
    assert_equal(0, #win.visible_rows, "visible_rows should be empty")

    local lines = vim.api.nvim_buf_get_lines(win.buf_id, 0, -1, false)
    local found_placeholder = false
    for _, line in ipairs(lines) do
        if line:find("%(no files match%)") then
            found_placeholder = true
            break
        end
    end
    assert_true(found_placeholder, "should show no files match placeholder")

    home_window._close()
end

local function test_move_selection_noop_when_empty()
    local entries = {}
    home_window.open(make_opts(entries))

    local win = home_window._get_window()
    assert_not_nil(win, "active window should exist")

    -- Should not error
    win:move_selection(1)
    win:move_selection(-1)
    assert_equal(1, win.selected_index, "selection should stay at 1")

    home_window._close()
end

local function test_filter_resets_selection()
    home_window.open(make_opts())

    local win = home_window._get_window()
    assert_not_nil(win, "active window should exist")

    -- Move selection down
    win:move_selection(1)
    assert_true(win.selected_index > 1, "selection should have moved")

    -- Cycling filter should reset selection to 1
    win:cycle_filter()
    assert_equal(1, win.selected_index, "filter cycling should reset selection to 1")

    home_window._close()
end

local function test_cursorline_disabled()
    home_window.open(make_opts())

    local win = home_window._get_window()
    assert_not_nil(win, "active window should exist")

    local cursorline = vim.api.nvim_get_option_value("cursorline", { win = win.win_id })
    assert_false(cursorline, "cursorline should be disabled")

    home_window._close()
end

function M.run()
    local runner = TestRunner.new("home_window")

    runner:test("open() creates a floating window", test_open_creates_floating_window)
    runner:test("open() enforces singleton", test_open_enforces_singleton)
    runner:test("_close() cleans up state and allows reopening", test_close_cleans_up_state)
    runner:test("filter cycling changes display", test_filter_cycling)
    runner:test("render formats lines correctly", test_render_formats_lines)
    runner:test("display entries sorted alphabetically", test_display_entries_sorted_alphabetically)
    runner:test("selection navigation with move_selection", test_selection_navigation)
    runner:test("selection wraps around", test_selection_wraparound)
    runner:test("filter hides files with zero matching issues", test_filter_hides_zero_count_files)
    runner:test("empty entries shows placeholder", test_no_entries_shows_placeholder)
    runner:test("move_selection no-op when empty", test_move_selection_noop_when_empty)
    runner:test("filter cycling resets selection", test_filter_resets_selection)
    runner:test("cursorline is disabled", test_cursorline_disabled)

    runner:run()
end

return M
