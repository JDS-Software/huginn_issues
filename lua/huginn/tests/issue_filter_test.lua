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

-- issue_filter_test.lua
-- Tests for shared issue filter cycling logic

local M = {}

local issue_filter = require("huginn.components.issue_filter")

local function make_issues()
    return {
        { id = "001", status = "OPEN" },
        { id = "002", status = "CLOSED" },
        { id = "003", status = "OPEN" },
    }
end

local function test_apply_filters_by_status()
    local issues = make_issues()

    local all = issue_filter.apply(issues, "all")
    assert_equal(3, #all, "all filter should return all issues")

    local open = issue_filter.apply(issues, "open")
    assert_equal(2, #open, "open filter should return 2 issues")

    local closed = issue_filter.apply(issues, "closed")
    assert_equal(1, #closed, "closed filter should return 1 issue")

    -- Deep copy
    all[1].id = "modified"
    assert_equal("001", issues[1].id, "original should not be modified")
end

local function test_next_cycles_through_filters()
    assert_equal("open", issue_filter.next("all"), "all -> open")
    assert_equal("closed", issue_filter.next("open"), "open -> closed")
    assert_equal("all", issue_filter.next("closed"), "closed -> all")
    assert_equal("all", issue_filter.next("unknown"), "unknown -> all")
end

function M.run()
    local runner = TestRunner.new("issue_filter")

    runner:test("apply() filters issues by status", test_apply_filters_by_status)
    runner:test("next() cycles through filters", test_next_cycles_through_filters)

    runner:run()
end

return M
