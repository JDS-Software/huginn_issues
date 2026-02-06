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

-- log_viewer_test.lua
-- Tests for the log viewer floating window component

local M = {}

local log_viewer = require("huginn.components.log_viewer")
local logging = require("huginn.modules.logging")

--- Create a test logger with some entries
---@return huginn.Logger
local function make_logger()
    local logger = logging.new(false, ".huginnlog")
    logger:log("INFO", "Test message one")
    logger:log("WARN", "Test message two")
    return logger
end

local function test_open_creates_floating_window()
    local logger = make_logger()

    log_viewer.open(logger)
    assert_true(log_viewer.is_open(), "viewer should be open after open()")

    log_viewer._close()
end

local function test_open_enforces_singleton()
    local logger = make_logger()

    log_viewer.open(logger)
    assert_true(log_viewer.is_open(), "viewer should be open after first open()")

    -- Second call should not crash and window should still be open
    log_viewer.open(logger)
    assert_true(log_viewer.is_open(), "viewer should still be open after second open()")

    log_viewer._close()
end

local function test_open_with_empty_buffer()
    local logger = logging.new(false, ".huginnlog")

    -- Should not crash with empty buffer
    log_viewer.open(logger)
    assert_true(log_viewer.is_open(), "viewer should be open with empty buffer")

    log_viewer._close()
end

local function test_close_cleans_up_and_allows_reopen()
    local logger = make_logger()

    log_viewer.open(logger)
    assert_true(log_viewer.is_open(), "viewer should be open")

    log_viewer._close()
    assert_false(log_viewer.is_open(), "viewer should be closed after _close()")

    -- Should be able to reopen
    log_viewer.open(logger)
    assert_true(log_viewer.is_open(), "viewer should be open after reopen")

    log_viewer._close()
end

function M.run()
    local runner = TestRunner.new("log_viewer")

    runner:test("open() creates a floating window", test_open_creates_floating_window)
    runner:test("open() enforces singleton", test_open_enforces_singleton)
    runner:test("open() with empty buffer doesn't crash", test_open_with_empty_buffer)
    runner:test("_close() cleans up state and allows reopening", test_close_cleans_up_and_allows_reopen)

    runner:run()
end

return M
