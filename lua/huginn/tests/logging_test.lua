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

local M = {}

local logging = require("huginn.modules.logging")

local function test_new()
    -- defaults
    local logger = logging.new()
    assert_false(logger.enabled, "default enabled should be false")
    assert_equal(".huginnlog", logger.filepath, "default filepath")
    assert_equal(0, #logger.buffer, "buffer should be empty")
    assert_equal(0, logger.flushed_count, "flushed_count should be 0")

    -- explicit disabled
    local disabled = logging.new(false)
    assert_false(disabled.enabled, "enabled should be false")

    -- with args
    local tmp = vim.fn.tempname()
    local enabled = logging.new(true, tmp)
    assert_true(enabled.enabled, "enabled should be true")
    assert_equal(tmp, enabled.filepath, "filepath should match")
    assert_equal(0, #enabled.buffer, "buffer should be empty")
    assert_equal(0, enabled.flushed_count, "flushed_count should be 0")
    vim.api.nvim_create_augroup("HuginnLogging", { clear = true })
end

local function test_log_and_alert()
    local logger = logging.new()

    -- log appends with correct format across levels
    logger:log("INFO", "first")
    logger:log("WARN", "second")
    logger:log("ERROR", "third")
    assert_equal(3, #logger.buffer, "buffer should have three entries")
    assert_match("%[%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d%] INFO: first", logger.buffer[1], "first entry format")
    assert_match("%] WARN: second", logger.buffer[2], "second entry")
    assert_match("%] ERROR: third", logger.buffer[3], "third entry")

    -- alert uses same format and appends to same buffer
    logger:alert("WARN", "alert test")
    assert_equal(4, #logger.buffer, "alert should add to buffer")
    assert_match("%[%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d%] WARN: alert test", logger.buffer[4], "alert format")
end

local function test_flush()
    -- disabled: no file created
    local disabled = logging.new(false)
    disabled:log("INFO", "should not write")
    local tmp_disabled = vim.fn.tempname()
    disabled.filepath = tmp_disabled
    disabled:flush()
    assert_false(vim.fn.filereadable(tmp_disabled) == 1, "file should not be created when disabled")

    -- basic write
    local tmp = vim.fn.tempname()
    local logger = logging.new(true, tmp)
    logger:log("INFO", "line one")
    logger:log("WARN", "line two")
    logger:flush()
    local lines = vim.fn.readfile(tmp)
    assert_equal(2, #lines, "file should have two lines")
    assert_match("INFO: line one", lines[1], "first file line")
    assert_match("WARN: line two", lines[2], "second file line")
    assert_equal(2, logger.flushed_count, "flushed_count should be 2")

    -- incremental: second flush appends
    logger:log("WARN", "batch two a")
    logger:log("WARN", "batch two b")
    logger:flush()
    lines = vim.fn.readfile(tmp)
    assert_equal(4, #lines, "file should have four lines after two flushes")
    assert_match("batch two a", lines[3], "third line")
    assert_match("batch two b", lines[4], "fourth line")
    assert_equal(4, logger.flushed_count, "flushed_count should be 4")

    -- no new lines: flush is noop
    local count_before = logger.flushed_count
    logger:flush()
    assert_equal(count_before, logger.flushed_count, "flushed_count should not change")
    lines = vim.fn.readfile(tmp)
    assert_equal(4, #lines, "file should still have four lines")

    os.remove(tmp)
    vim.api.nvim_create_augroup("HuginnLogging", { clear = true })
end

local function test_configure()
    -- enable from disabled
    local logger = logging.new()
    assert_false(logger.enabled, "should start disabled")
    local tmp = vim.fn.tempname()
    logger:configure(true, tmp)
    assert_true(logger.enabled, "should be enabled after configure")
    assert_equal(tmp, logger.filepath, "filepath should be updated")

    -- disable from enabled
    logger:configure(false)
    assert_false(logger.enabled, "should be disabled after configure")

    -- preserves buffer across configure
    local logger2 = logging.new()
    logger2:log("INFO", "before configure")
    logger2:log("WARN", "also before")
    logger2:configure(true, vim.fn.tempname())
    assert_equal(2, #logger2.buffer, "buffer should retain pre-configure entries")
    assert_match("before configure", logger2.buffer[1], "first entry preserved")
    assert_match("also before", logger2.buffer[2], "second entry preserved")

    -- updates filepath while staying disabled
    local logger3 = logging.new()
    local new_path = vim.fn.tempname()
    logger3:configure(false, new_path)
    assert_false(logger3.enabled, "should remain disabled")
    assert_equal(new_path, logger3.filepath, "filepath should be updated")

    -- nil filepath keeps current
    local logger4 = logging.new(false, "/original/path")
    logger4:configure(false, nil)
    assert_equal("/original/path", logger4.filepath, "filepath should not change when nil")

    -- flush works after enable with pre-configure entries
    local tmp2 = vim.fn.tempname()
    local logger5 = logging.new()
    logger5:log("INFO", "pre-configure line")
    logger5:configure(true, tmp2)
    logger5:log("INFO", "post-configure line")
    logger5:flush()
    local lines = vim.fn.readfile(tmp2)
    assert_equal(2, #lines, "both pre and post configure lines should flush")
    assert_match("pre%-configure line", lines[1], "pre-configure line in file")
    assert_match("post%-configure line", lines[2], "post-configure line in file")

    os.remove(tmp2)
    vim.api.nvim_create_augroup("HuginnLogging", { clear = true })
end

local function test_get_buffer()
    -- with entries
    local logger = logging.new()
    logger:log("INFO", "one")
    logger:log("WARN", "two")
    local buf = logger:get_buffer()
    assert_equal(2, #buf, "get_buffer should return buffer with two entries")
    assert_match("INFO: one", buf[1], "first buffer entry")
    assert_match("WARN: two", buf[2], "second buffer entry")

    -- empty
    local empty = logging.new()
    local empty_buf = empty:get_buffer()
    assert_equal(0, #empty_buf, "get_buffer should return empty buffer")
end

function M.run()
    local runner = TestRunner.new("logging")

    runner:test("new() constructs with correct defaults and args", test_new)
    runner:test("log() and alert() append formatted entries to buffer", test_log_and_alert)
    runner:test("flush() writes buffer to file incrementally", test_flush)
    runner:test("configure() toggles state and preserves buffer", test_configure)
    runner:test("get_buffer() returns buffer contents", test_get_buffer)

    runner:run()
end

return M
