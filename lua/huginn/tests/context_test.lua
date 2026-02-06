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

-- context_test.lua
-- Tests for the plugin context module

local M = {}

local context = require("huginn.modules.context")
local config = require("huginn.modules.config")
local filepath = require("huginn.modules.filepath")
local logging = require("huginn.modules.logging")

--- Create a temp directory with a .huginn file
---@param content string? .huginn file content (defaults to empty)
---@return string dir absolute path to temp directory
---@return string huginn_path absolute path to .huginn file
local function create_temp_project(content)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local huginn_path = dir .. "/.huginn"
    vim.fn.writefile(vim.split(content or "", "\n"), huginn_path)
    return dir, huginn_path
end

--- Remove a temp directory and its contents
---@param dir string absolute path to directory
local function cleanup_temp_project(dir)
    vim.fn.delete(dir, "rf")
end

--- Create a bootstrap logger for testing
---@return huginn.Logger
local function make_logger()
    return logging.new()
end

--- Reset context and config module state between tests
local function reset()
    context._reset()
    config.active = {}
    config.huginn_path = nil
end

local function test_init()
    -- get() returns nil before init
    reset()
    assert_nil(context.get(), "get() should return nil before init")

    -- error when no .huginn file exists
    reset()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    local err_result, err = context.init(tmp, make_logger())
    assert_nil(err_result, "init should return nil when no .huginn exists")
    assert_not_nil(err, "init should return error when no .huginn exists")
    vim.fn.delete(tmp, "rf")

    -- success: returns context with cwd and config defaults
    reset()
    local dir = create_temp_project("")
    local result, init_err = context.init(dir, make_logger())
    assert_not_nil(result, "init should return context")
    assert_nil(init_err, "init should not return error")
    assert_equal(filepath.normalize(dir), result.cwd, "cwd should be the .huginn directory")
    assert_not_nil(result.config, "config should be set")
    assert_not_nil(result.config.plugin, "config should have plugin section")
    assert_equal("issues", result.config.plugin.issue_dir, "config should have defaults")
    cleanup_temp_project(dir)

    -- config reflects user overrides
    reset()
    local dir2 = create_temp_project("[plugin]\nissue_dir = custom")
    local result2 = context.init(dir2, make_logger())
    assert_equal("custom", result2.config.plugin.issue_dir, "config should reflect user overrides")
    cleanup_temp_project(dir2)
end

local function test_init_logger()
    -- stores the bootstrap logger on context
    reset()
    local dir = create_temp_project("")
    local logger = make_logger()
    local result = context.init(dir, logger)
    assert_equal(logger, result.logger, "context should store the bootstrap logger")
    cleanup_temp_project(dir)

    -- configures logger from config
    reset()
    local dir2 = create_temp_project("[logging]\nenabled = true\nfilepath = test.log")
    local logger2 = make_logger()
    assert_false(logger2.enabled, "logger should start disabled")
    context.init(dir2, logger2)
    assert_true(logger2.enabled, "logger should be enabled after init")
    local expected_path = filepath.join(filepath.normalize(dir2), "test.log")
    assert_equal(expected_path, logger2.filepath, "logger filepath should be resolved to absolute")
    cleanup_temp_project(dir2)
    vim.api.nvim_create_augroup("HuginnLogging", { clear = true })

    -- preserves bootstrap log buffer
    reset()
    local dir3 = create_temp_project("")
    local logger3 = make_logger()
    logger3:log("INFO", "bootstrap message")
    context.init(dir3, logger3)
    assert_equal(1, #logger3:get_buffer(), "bootstrap log lines should be preserved")
    assert_match("bootstrap message", logger3:get_buffer()[1], "bootstrap message content")
    cleanup_temp_project(dir3)
end

local function test_get_lifecycle()
    -- returns singleton after init
    reset()
    local dir = create_temp_project("")
    local from_init = context.init(dir, make_logger())
    local from_get = context.get()
    assert_equal(from_init, from_get, "get() should return the same instance as init()")

    -- returns nil after reset
    context._reset()
    assert_nil(context.get(), "get() should return nil after reset")
    cleanup_temp_project(dir)
end

local function test_from_command_normal_mode()
    reset()
    local dir = create_temp_project("")
    local logger = make_logger()
    context.init(dir, logger)

    -- Create a buffer and make it current
    local buf = vim.api.nvim_create_buf(true, false)
    local source = dir .. "/test.lua"
    vim.api.nvim_buf_set_name(buf, source)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line one", "line two", "line three" })
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { 2, 5 })

    -- Normal mode invocation (range = 0)
    local cmd_ctx, err = context.from_command({ range = 0 })
    assert_not_nil(cmd_ctx, "from_command should return context")
    assert_nil(err, "from_command should not return error")
    assert_equal(buf, cmd_ctx.buffer, "buffer should match current buffer")
    assert_not_nil(cmd_ctx.window, "window state should be present")
    assert_equal(source, cmd_ctx.window.filepath, "filepath should match buffer name")
    assert_equal("n", cmd_ctx.window.mode, "mode should be 'n' for normal")
    assert_equal(2, cmd_ctx.window.start.line, "start line should match cursor row")
    assert_equal(6, cmd_ctx.window.start.col, "start col should be cursor col + 1 (1-based)")
    assert_nil(cmd_ctx.window.finish, "finish should be nil in normal mode")

    vim.api.nvim_set_option_value("modified", false, { buf = buf })
    vim.api.nvim_buf_delete(buf, { force = true })
    cleanup_temp_project(dir)
end

local function test_from_command_no_context()
    reset()
    local cmd_ctx, err = context.from_command({ range = 0 })
    assert_nil(cmd_ctx, "from_command should return nil without context")
    assert_not_nil(err, "from_command should return error without context")
end

local function test_config_change_lifecycle()
    -- BufWritePost on .huginn fires listeners with updated config
    reset()
    local dir, huginn_path = create_temp_project("[plugin]\nissue_dir = original")
    local logger = make_logger()
    context.init(dir, logger)
    context.setup(logger)

    local received = nil
    context.on_config_change(function(cfg)
        received = cfg
    end)

    -- Open .huginn in a buffer, modify on disk, fire autocmd
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, huginn_path)
    vim.fn.writefile(vim.split("[plugin]\nissue_dir = changed", "\n"), huginn_path)
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf })

    assert_not_nil(received, "listener should have been called")
    assert_equal("changed", received.plugin.issue_dir, "listener should receive updated config")
    assert_equal("changed", context.get().config.plugin.issue_dir, "instance config should be updated")

    -- multiple listeners all fire
    local call_count = 0
    context.on_config_change(function() call_count = call_count + 1 end)
    context.on_config_change(function() call_count = call_count + 1 end)
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf })
    assert_equal(2, call_count, "both listeners should have fired")

    -- _reset clears listeners
    context._reset()
    local called_after_reset = false
    context.on_config_change(function() called_after_reset = true end)
    config.huginn_path = nil
    config.active = {}
    context.init(dir, make_logger())
    context.setup(logger)
    vim.fn.writefile(vim.split("[plugin]\nissue_dir = again", "\n"), huginn_path)
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf })
    assert_true(called_after_reset, "listener registered after reset should fire")

    vim.api.nvim_set_option_value("modified", false, { buf = buf })
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.api.nvim_create_augroup("HuginnConfig", { clear = true })
    cleanup_temp_project(dir)
end

function M.run()
    local runner = TestRunner.new("context")

    runner:test("init validates input and populates context fields", test_init)
    runner:test("init configures and preserves logger", test_init_logger)
    runner:test("get returns singleton after init and nil after reset", test_get_lifecycle)
    runner:test("from_command builds context in normal mode", test_from_command_normal_mode)
    runner:test("from_command returns error without context", test_from_command_no_context)
    runner:test("config change callbacks and reset lifecycle", test_config_change_lifecycle)

    runner:run()
end

return M
