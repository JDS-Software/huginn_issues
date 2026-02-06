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

-- confirm_test.lua
-- Tests for the confirmation dialog component

local M = {}

local confirm = require("huginn.components.confirm")

--- Save vim.ui.select and replace with a mock that returns mock_choice
---@param mock_choice string|nil the choice the mock will return
---@return table captured table with .items, .opts fields after show() runs
local function mock_select(mock_choice)
    local original = vim.ui.select
    local captured = {}

    vim.ui.select = function(items, opts, callback)
        captured.items = items
        captured.opts = opts
        callback(mock_choice)
    end

    captured._restore = function()
        vim.ui.select = original
    end

    return captured
end

local function test_show_rejects_invalid_input()
    -- nil and non-function callbacks don't crash
    assert_true(pcall(confirm.show, "message", nil), "should not crash with nil callback")
    assert_true(pcall(confirm.show, "message", "not a function"), "should not crash with non-function callback")

    -- nil opts, empty message, missing message all yield false
    local results = {}
    confirm.show(nil, function(c) results[1] = c end)
    confirm.show({ message = "" }, function(c) results[2] = c end)
    confirm.show({}, function(c) results[3] = c end)
    assert_false(results[1], "nil opts should yield false")
    assert_false(results[2], "empty message should yield false")
    assert_false(results[3], "missing message should yield false")
end

local function test_show_builds_correct_dialog()
    -- string shorthand calls vim.ui.select with [Safe] default and Yes/No items
    local captured = mock_select("Yes")
    confirm.show("Delete this issue?", function() end)
    assert_not_nil(captured.items, "vim.ui.select should have been called")
    assert_equal(2, #captured.items, "should have two items")
    assert_equal("Yes", captured.items[1], "first item should be Yes")
    assert_equal("No", captured.items[2], "second item should be No")
    assert_match("^%[Safe%]", captured.opts.prompt, "string shorthand should default to [Safe]")
    assert_match("Delete this issue%?", captured.opts.prompt, "prompt should include message")
    captured._restore()

    -- level variants
    captured = mock_select("Yes")
    confirm.show({ message = "Delete?", level = "danger" }, function() end)
    assert_match("^%[Danger%]", captured.opts.prompt, "prompt should start with [Danger]")
    captured._restore()

    captured = mock_select("Yes")
    confirm.show({ message = "Overwrite?", level = "caution" }, function() end)
    assert_match("^%[Caution%]", captured.opts.prompt, "prompt should start with [Caution]")
    captured._restore()

    captured = mock_select("Yes")
    confirm.show({ message = "Continue?" }, function() end)
    assert_match("^%[Safe%]", captured.opts.prompt, "unspecified level should default to [Safe]")
    captured._restore()
end

local function test_show_callback_reflects_choice()
    -- Yes yields true
    local captured = mock_select("Yes")
    local yes_result = nil
    confirm.show("Confirm?", function(c) yes_result = c end)
    assert_true(yes_result, "selecting Yes should yield true")
    captured._restore()

    -- No yields false
    captured = mock_select("No")
    local no_result = nil
    confirm.show("Confirm?", function(c) no_result = c end)
    assert_false(no_result, "selecting No should yield false")
    captured._restore()

    -- Dismissal yields false
    captured = mock_select(nil)
    local dismiss_result = nil
    confirm.show("Confirm?", function(c) dismiss_result = c end)
    assert_false(dismiss_result, "dismissal should yield false")
    captured._restore()
end

function M.run()
    local runner = TestRunner.new("confirm")

    runner:test("show rejects invalid input gracefully", test_show_rejects_invalid_input)
    runner:test("show builds correct dialog with level and items", test_show_builds_correct_dialog)
    runner:test("show callback reflects user choice", test_show_callback_reflects_choice)

    runner:run()
end

return M
