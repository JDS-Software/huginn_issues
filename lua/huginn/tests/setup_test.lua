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

-- setup_test.lua
-- Tests for the plugin setup function

local M = {}

local context = require("huginn.modules.context")
local config = require("huginn.modules.config")
local filepath = require("huginn.modules.filepath")
local huginn = require("huginn")

--- Create a temp directory with a .huginn file
---@param content string? .huginn file content (defaults to empty)
---@return string dir absolute path to temp directory
local function create_temp_project(content)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local huginn_path = dir .. "/.huginn"
    vim.fn.writefile(vim.split(content or "", "\n"), huginn_path)
    return dir
end

--- Remove a temp directory and its contents
---@param dir string absolute path to directory
local function cleanup_temp_project(dir)
    vim.fn.delete(dir, "rf")
end

--- Reset all module state between tests
local function reset()
    context._reset()
    config.active = {}
    config.huginn_path = nil
    vim.api.nvim_create_augroup("HuginnConfig", { clear = true })
    vim.api.nvim_create_augroup("HuginnLogging", { clear = true })
end

--- Run a test inside a temporary directory, restoring cwd afterward
---@param dir string absolute path to cd into
---@param fn function test body
local function with_cwd(dir, fn)
    local saved_cwd = vim.fn.getcwd()
    vim.cmd("cd " .. vim.fn.fnameescape(dir))
    fn()
    vim.cmd("cd " .. vim.fn.fnameescape(saved_cwd))
end

local function test_setup_happy_path()
    -- initializes context with cwd, config defaults, logger, and success message
    reset()
    local dir = create_temp_project("")
    with_cwd(dir, function()
        huginn.setup()
        local ctx = context.get()
        assert_not_nil(ctx, "context should be initialized after setup")
        assert_equal(filepath.normalize(dir), ctx.cwd, "context cwd should match project dir")
        assert_not_nil(ctx.config, "config should be populated")
        assert_equal("issues", ctx.config.plugin.issue_dir, "plugin.issue_dir should default to issues")
        assert_not_nil(ctx.logger, "logger should be attached to context")
        local found = false
        for _, line in ipairs(ctx.logger:get_buffer()) do
            if line:match("Huginn initialized") then
                found = true
                break
            end
        end
        assert_true(found, "logger buffer should contain initialization success message")
    end)
    cleanup_temp_project(dir)

    -- accepts nil and empty table opts without error
    reset()
    local dir2 = create_temp_project("")
    with_cwd(dir2, function()
        assert_true(pcall(huginn.setup, nil), "setup should accept nil opts")
        reset()
        assert_true(pcall(huginn.setup, {}), "setup should accept empty table opts")
    end)
    cleanup_temp_project(dir2)
end

local function test_setup_no_huginn()
    reset()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    with_cwd(dir, function()
        assert_true(pcall(huginn.setup), "setup should not raise when no .huginn exists")
        assert_nil(context.get(), "context should be nil when no .huginn exists")
    end)
    vim.fn.delete(dir, "rf")
end

local function test_setup_logger_bootstrap()
    -- enabled when config says so
    reset()
    local dir = create_temp_project("[logging]\nenabled = true\nfilepath = test.log")
    with_cwd(dir, function()
        huginn.setup()
        assert_true(context.get().logger.enabled, "logger should be enabled when config says so")
    end)
    cleanup_temp_project(dir)
    vim.api.nvim_create_augroup("HuginnLogging", { clear = true })

    -- stays disabled by default
    reset()
    local dir2 = create_temp_project("")
    with_cwd(dir2, function()
        huginn.setup()
        assert_false(context.get().logger.enabled, "logger should remain disabled when config says so")
    end)
    cleanup_temp_project(dir2)
end

function M.run()
    local runner = TestRunner.new("setup")

    runner:test("setup initializes context with valid project", test_setup_happy_path)
    runner:test("setup is dormant when no .huginn exists", test_setup_no_huginn)
    runner:test("setup configures logger from .huginn config", test_setup_logger_bootstrap)

    runner:run()
end

return M
