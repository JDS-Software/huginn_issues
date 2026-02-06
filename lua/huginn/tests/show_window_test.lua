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

-- show_window_test.lua
-- Tests for the show window floating window component

local M = {}

local show_window = require("huginn.components.show_window")

--- Build a minimal issue object for testing
---@param id string
---@param status string "OPEN"|"CLOSED"
---@param desc string? description text
---@return huginn.HuginnIssue
local function make_issue(id, status, desc)
    local blocks = {}
    if desc then blocks["Issue Description"] = desc end
    return {
        id = id,
        version = 1,
        status = status,
        location = { filepath = "src/main.lua", reference = {} },
        blocks = blocks,
        mtime = 0,
    }
end

--- Build default opts for show_window.open
---@param issues huginn.HuginnIssue[]?
---@return table
local function make_opts(issues)
    return {
        issues = issues or {
            make_issue("20260110_140000", "OPEN", "First issue."),
            make_issue("20260110_150000", "CLOSED", "Second issue."),
        },
        header_context = "src/main.lua",
        source_filepath = "src/main.lua",
        source_bufnr = vim.api.nvim_get_current_buf(),
        context = { config = { show = { description_length = 80 } } },
    }
end

local function test_open_creates_floating_window()
    show_window.open(make_opts())
    assert_true(show_window.is_open(), "show window should be open after open()")

    show_window._close()
end

local function test_open_enforces_singleton()
    show_window.open(make_opts())
    assert_true(show_window.is_open(), "show window should be open after first open()")

    show_window.open(make_opts())
    assert_true(show_window.is_open(), "show window should still be open after second open()")

    show_window._close()
end

local function test_close_cleans_up_state()
    show_window.open(make_opts())
    assert_true(show_window.is_open(), "show window should be open")

    show_window._close()
    assert_false(show_window.is_open(), "show window should be closed after _close()")

    -- Should be able to reopen
    show_window.open(make_opts())
    assert_true(show_window.is_open(), "show window should be open after reopen")

    show_window._close()
end

local function test_filter_cycling()
    show_window.open(make_opts())

    local win = show_window._get_window()
    assert_not_nil(win, "active window should exist")
    assert_equal("all", win.filter, "initial filter should be 'all'")
    assert_equal(2, #win.display_issues, "all filter should show 2 issues")

    -- Cycle to open
    win:cycle_filter()
    assert_equal("open", win.filter, "filter should cycle to 'open'")
    assert_equal(1, #win.display_issues, "open filter should show 1 issue")

    -- Cycle to closed
    win:cycle_filter()
    assert_equal("closed", win.filter, "filter should cycle to 'closed'")
    assert_equal(1, #win.display_issues, "closed filter should show 1 issue")

    -- Cycle back to all
    win:cycle_filter()
    assert_equal("all", win.filter, "filter should cycle back to 'all'")
    assert_equal(2, #win.display_issues, "all filter should show 2 issues again")

    show_window._close()
end

local function test_render_formats_issue_lines()
    local issues = {
        make_issue("20260110_140000", "OPEN", "First issue."),
        make_issue("20260110_150000", "CLOSED", "Second issue."),
    }
    show_window.open(make_opts(issues))

    local win = show_window._get_window()
    assert_not_nil(win, "active window should exist")
    assert_not_nil(win.buf_id, "buffer should exist")

    local lines = vim.api.nvim_buf_get_lines(win.buf_id, 0, -1, false)

    -- Line 1: header with context and filter label
    assert_match("src/main.lua", lines[1], "header should contain filepath")
    assert_match("%[Filter: ALL%]", lines[1], "header should contain filter label")

    -- Line 2: separator (─ is multi-byte UTF-8, so check with find)
    assert_true(lines[2]:find("─") == 1, "line 2 should start with separator character")
    assert_true(#lines[2] > 0, "line 2 should not be empty")

    -- Lines 3-4: issue lines
    assert_true(#lines >= 6, "should have at least 6 lines (header + sep + 2 issues + sep + help)")
    assert_match("%[OPEN%]", lines[3], "first issue line should show OPEN status")
    assert_match("20260110_140000", lines[3], "first issue line should show issue ID")
    assert_match("%[CLOSED%]", lines[4], "second issue line should show CLOSED status")

    -- Footer: separator + help text
    assert_true(lines[5]:find("─") == 1, "line 5 should be a footer separator")
    assert_match("C%-f filter", lines[6], "last line should show keyboard shortcuts")

    show_window._close()
end

function M.run()
    local runner = TestRunner.new("show_window")

    runner:test("open() creates a floating window", test_open_creates_floating_window)
    runner:test("open() enforces singleton", test_open_enforces_singleton)
    runner:test("_close() cleans up state and allows reopening", test_close_cleans_up_state)
    runner:test("filter cycling changes display", test_filter_cycling)
    runner:test("render formats issue lines correctly", test_render_formats_issue_lines)

    runner:run()
end

return M
