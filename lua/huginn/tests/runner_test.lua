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

-- runner_test.lua
-- Tests for the test runner framework
-- Verifies assertions and TestRunner functionality work correctly

local M = {}

local function test_assert_equal()
    assert_equal("hello", "hello")
    assert_equal(42, 42)
    assert_equal(true, true)
    assert_equal(false, false)
    assert_equal(nil, nil)
    -- rejects unequal values
    local success = pcall(assert_equal, "a", "b")
    assert_false(success, "assert_equal should fail for unequal values")
end

local function test_assert_true_and_false()
    assert_true(true)
    assert_false(false)
    -- inverted inputs raise
    local true_fail = pcall(assert_true, false)
    assert_false(true_fail, "assert_true should fail for false")
    local false_fail = pcall(assert_false, true)
    assert_false(false_fail, "assert_false should fail for true")
end

local function test_assert_nil_and_not_nil()
    assert_nil(nil)
    assert_not_nil("value")
    assert_not_nil(0)
    assert_not_nil(false)
    assert_not_nil({})
    -- inverted inputs raise
    local nil_fail = pcall(assert_nil, "not nil")
    assert_false(nil_fail, "assert_nil should fail for non-nil values")
    local not_nil_fail = pcall(assert_not_nil, nil)
    assert_false(not_nil_fail, "assert_not_nil should fail for nil")
end

local function test_assert_match()
    assert_match("hello", "hello world")
    assert_match("^hello", "hello world")
    assert_match("world$", "hello world")
    assert_match("%d+", "test123")
    -- rejects non-matching pattern
    local success = pcall(assert_match, "xyz", "hello world")
    assert_false(success, "assert_match should fail for non-matching patterns")
end

function M.run()
    local runner = TestRunner.new("runner")

    runner:test("assert_equal accepts matching values and rejects mismatches", test_assert_equal)
    runner:test("assert_true/assert_false accept correct booleans and reject inverted", test_assert_true_and_false)
    runner:test("assert_nil/assert_not_nil accept correct nullity and reject inverted", test_assert_nil_and_not_nil)
    runner:test("assert_match accepts matching patterns and rejects non-matching", test_assert_match)

    runner:run()
end

return M
