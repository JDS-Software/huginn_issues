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

-- issue_picker_test.lua
-- Tests for the issue_picker floating window component

local M = {}

local issue_picker = require("huginn.components.issue_picker")

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

--- Build default opts for issue_picker.open
---@param issues huginn.HuginnIssue[]?
---@return table
local function make_opts(issues)
    return {
        issues = issues or {
            make_issue("20260110_140000", "OPEN", "First issue."),
            make_issue("20260110_150000", "CLOSED", "Second issue."),
        },
        header_context = "Add: src/main.lua > my_func",
        context = { config = { show = { description_length = 80 } } },
    }
end

local function test_open_creates_floating_window()
    local called = false
    issue_picker.open(make_opts(), function() called = true end)
    assert_true(issue_picker.is_open(), "picker should be open after open()")

    issue_picker._close()
    -- WinClosed fires callback(nil) asynchronously, but _close deactivates directly
end

local function test_open_enforces_singleton()
    local call_count = 0
    issue_picker.open(make_opts(), function() call_count = call_count + 1 end)
    assert_true(issue_picker.is_open(), "picker should be open after first open()")

    -- Second open should just focus
    issue_picker.open(make_opts(), function() call_count = call_count + 1 end)
    assert_true(issue_picker.is_open(), "picker should still be open after second open()")

    issue_picker._close()
end

local function test_close_cleans_up_state()
    issue_picker.open(make_opts(), function() end)
    assert_true(issue_picker.is_open(), "picker should be open")

    issue_picker._close()
    assert_false(issue_picker.is_open(), "picker should be closed after _close()")

    -- Should be able to reopen
    issue_picker.open(make_opts(), function() end)
    assert_true(issue_picker.is_open(), "picker should be open after reopen")

    issue_picker._close()
end

local function test_filter_cycling()
    issue_picker.open(make_opts(), function() end)

    local picker = issue_picker._get_picker()
    assert_not_nil(picker, "active picker should exist")
    assert_equal("all", picker.filter, "initial filter should be 'all'")
    assert_equal(2, #picker.display_issues, "all filter should show 2 issues")

    -- Cycle to open
    picker:cycle_filter()
    assert_equal("open", picker.filter, "filter should cycle to 'open'")
    assert_equal(1, #picker.display_issues, "open filter should show 1 issue")

    -- Cycle to closed
    picker:cycle_filter()
    assert_equal("closed", picker.filter, "filter should cycle to 'closed'")
    assert_equal(1, #picker.display_issues, "closed filter should show 1 issue")

    -- Cycle back to all
    picker:cycle_filter()
    assert_equal("all", picker.filter, "filter should cycle back to 'all'")
    assert_equal(2, #picker.display_issues, "all filter should show 2 issues again")

    issue_picker._close()
end

local function test_render_formats_issue_lines()
    local issues = {
        make_issue("20260110_140000", "OPEN", "First issue."),
        make_issue("20260110_150000", "CLOSED", "Second issue."),
    }
    issue_picker.open(make_opts(issues), function() end)

    local picker = issue_picker._get_picker()
    assert_not_nil(picker, "active picker should exist")
    assert_not_nil(picker.buf_id, "buffer should exist")

    local lines = vim.api.nvim_buf_get_lines(picker.buf_id, 0, -1, false)

    -- Line 1: header with context and filter label
    assert_match("Add: src/main.lua > my_func", lines[1], "header should contain context")
    assert_match("%[Filter: ALL%]", lines[1], "header should contain filter label")

    -- Line 2: separator
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

    issue_picker._close()
end

local function test_callback_fires_nil_on_dismiss()
    local received = "sentinel"
    issue_picker.open(make_opts(), function(id) received = id end)

    local picker = issue_picker._get_picker()
    assert_not_nil(picker, "active picker should exist")

    picker:dismiss()
    assert_nil(received, "callback should receive nil on dismiss")
end

local function test_callback_fires_issue_id_on_select()
    local received = nil
    issue_picker.open(make_opts(), function(id) received = id end)

    local picker = issue_picker._get_picker()
    assert_not_nil(picker, "active picker should exist")

    -- Cursor should be on line 3 (first issue)
    picker:select()
    assert_equal("20260110_140000", received, "callback should receive issue ID of first issue")
end

local function test_double_fire_guard()
    local call_count = 0
    issue_picker.open(make_opts(), function() call_count = call_count + 1 end)

    local picker = issue_picker._get_picker()
    assert_not_nil(picker, "active picker should exist")

    picker:dismiss()
    assert_equal(1, call_count, "callback should fire once on dismiss")

    -- Try to fire again
    picker:dismiss()
    assert_equal(1, call_count, "callback should not fire again (double-fire guard)")

    -- Also try select after dismiss
    picker:select()
    assert_equal(1, call_count, "callback should not fire via select after dismiss")
end

local function test_noop_when_callback_missing()
    -- Should not error when callback is nil/missing
    issue_picker.open(make_opts(), nil)
    assert_false(issue_picker.is_open(), "picker should not open without callback")
end

local function test_callback_nil_when_opts_invalid()
    local received = "sentinel"
    issue_picker.open({}, function(id) received = id end)
    assert_nil(received, "callback should receive nil for empty issues")
    assert_false(issue_picker.is_open(), "picker should not open with empty opts")
end

local function test_callback_nil_when_issues_empty()
    local received = "sentinel"
    issue_picker.open({ issues = {} }, function(id) received = id end)
    assert_nil(received, "callback should receive nil for empty issues list")
    assert_false(issue_picker.is_open(), "picker should not open with empty issues")
end

function M.run()
    local runner = TestRunner.new("issue_picker")

    runner:test("open() creates a floating window", test_open_creates_floating_window)
    runner:test("open() enforces singleton", test_open_enforces_singleton)
    runner:test("_close() cleans up state and allows reopening", test_close_cleans_up_state)
    runner:test("filter cycling changes display", test_filter_cycling)
    runner:test("render formats issue lines correctly", test_render_formats_issue_lines)
    runner:test("callback fires nil on dismiss", test_callback_fires_nil_on_dismiss)
    runner:test("callback fires issue_id on select", test_callback_fires_issue_id_on_select)
    runner:test("double-fire guard prevents duplicate callbacks", test_double_fire_guard)
    runner:test("no-op when callback is missing", test_noop_when_callback_missing)
    runner:test("callback(nil) when opts invalid", test_callback_nil_when_opts_invalid)
    runner:test("callback(nil) when issues empty", test_callback_nil_when_issues_empty)

    runner:run()
end

return M
