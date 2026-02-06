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

-- config_test.lua
-- Tests for the config module

local M = {}

local config = require("huginn.modules.config")
local filepath = require("huginn.modules.filepath")

--- Write a temp .huginn file and return its absolute path
---@param content string file content
---@return string path absolute path to temp file
local function write_temp_huginn(content)
    local path = vim.fn.tempname() .. ".huginn"
    vim.fn.writefile(vim.split(content, "\n"), path)
    return path
end

--- Create a mock logger that captures alerts
---@return { alert: fun(self, level: string, message: string), alerts: {level: string, message: string}[] }
local function mock_logger()
    local logger = { alerts = {} }
    function logger:alert(level, message)
        table.insert(self.alerts, { level = level, message = message })
    end

    function logger:log(_, _) end

    return logger
end

--- Reset config module state between tests
local function reset_config()
    config.active = {}
    config.huginn_path = nil
end

local function test_generate_default_file()
    local result = config.generate_default_file()
    assert_equal("string", type(result))
    -- required sections
    assert_match("%[plugin%]", result)
    assert_match("%[logging%]", result)
    -- values are commented out with defaults
    assert_match("# issue_dir = issues", result)
    assert_match("# enabled = false", result)
    assert_match("# filepath = %.huginnlog", result)
end

local function test_load_rejects_invalid_paths()
    reset_config()
    local nil_result, nil_err = config.load(nil)
    assert_nil(nil_result)
    assert_not_nil(nil_err)

    reset_config()
    local empty_result, empty_err = config.load("")
    assert_nil(empty_result)
    assert_not_nil(empty_err)

    reset_config()
    local missing_result, missing_err = config.load("/nonexistent/path/.huginn")
    assert_nil(missing_result)
    assert_not_nil(missing_err)
end

local function test_load_empty_file_returns_defaults()
    reset_config()
    local path = write_temp_huginn("")
    local result = config.load(path, mock_logger())
    assert_not_nil(result)
    assert_equal("issues", result.plugin.issue_dir)
    assert_equal(false, result.logging.enabled)
    assert_equal(".huginnlog", result.logging.filepath)
    assert_equal(filepath.normalize(path), config.huginn_path)
    vim.fn.delete(path)
end

local function test_load_user_overrides()
    -- single-section override preserves other defaults
    reset_config()
    local path = write_temp_huginn("[logging]\nenabled = true")
    local result = config.load(path, mock_logger())
    assert_equal(true, result.logging.enabled)
    assert_equal(".huginnlog", result.logging.filepath)
    assert_equal("issues", result.plugin.issue_dir)
    vim.fn.delete(path)

    -- multi-section override
    reset_config()
    path = write_temp_huginn("[plugin]\nissue_dir = my_issues\n[logging]\nenabled = true")
    result = config.load(path, mock_logger())
    assert_equal("my_issues", result.plugin.issue_dir)
    assert_equal(true, result.logging.enabled)
    vim.fn.delete(path)
end

local function test_load_unknown_section_warns()
    reset_config()
    local path = write_temp_huginn("[bogus]\nkey = value")
    local logger = mock_logger()
    config.load(path, logger)
    assert_equal(1, #logger.alerts)
    assert_match("Unknown config section", logger.alerts[1].message)
    vim.fn.delete(path)
end

local function test_load_caching()
    -- same path returns cached result
    reset_config()
    local path = write_temp_huginn("[plugin]\nissue_dir = original")
    local result1 = config.load(path, mock_logger())
    assert_equal("original", result1.plugin.issue_dir)
    vim.fn.writefile(vim.split("[plugin]\nissue_dir = changed", "\n"), path)
    local result2 = config.load(path, mock_logger())
    assert_equal("original", result2.plugin.issue_dir)
    vim.fn.delete(path)

    -- different path forces reload
    reset_config()
    local path1 = write_temp_huginn("[plugin]\nissue_dir = first")
    local path2 = write_temp_huginn("[plugin]\nissue_dir = second")
    config.load(path1, mock_logger())
    assert_equal("first", config.active.plugin.issue_dir)
    config.load(path2, mock_logger())
    assert_equal("second", config.active.plugin.issue_dir)
    vim.fn.delete(path1)
    vim.fn.delete(path2)
end

local function test_load_unknown_key_warns()
    reset_config()
    local path = write_temp_huginn("[plugin]\nbogus = value")
    local logger = mock_logger()
    local result = config.load(path, logger)
    assert_equal(1, #logger.alerts)
    assert_match("Unknown config key", logger.alerts[1].message)
    assert_equal("issues", result.plugin.issue_dir)
    assert_nil(result.plugin.bogus)
    vim.fn.delete(path)
end

local function test_load_type_mismatch_keeps_default()
    reset_config()
    local path = write_temp_huginn("[index]\nkey_length = abc")
    local logger = mock_logger()
    local result = config.load(path, logger)
    assert_equal(1, #logger.alerts)
    assert_match("Invalid value", logger.alerts[1].message)
    assert_equal(16, result.index.key_length)
    vim.fn.delete(path)
end

local function test_load_range_violation_keeps_default()
    reset_config()
    local path = write_temp_huginn("[index]\nkey_length = 100")
    local logger = mock_logger()
    local result = config.load(path, logger)
    assert_equal(1, #logger.alerts)
    assert_match("Invalid value", logger.alerts[1].message)
    assert_equal(16, result.index.key_length)
    vim.fn.delete(path)
end

local function test_load_invalid_color_keeps_default()
    reset_config()
    local path = write_temp_huginn("[annotation]\nbackground = not-a-color")
    local logger = mock_logger()
    local result = config.load(path, logger)
    assert_equal(1, #logger.alerts)
    assert_match("Invalid value", logger.alerts[1].message)
    assert_equal("#ffffff", result.annotation.background)
    vim.fn.delete(path)
end

local function test_load_valid_color_override()
    reset_config()
    local path = write_temp_huginn("[annotation]\nforeground = #abCDef")
    local logger = mock_logger()
    local result = config.load(path, logger)
    assert_equal(0, #logger.alerts)
    assert_equal("#abCDef", result.annotation.foreground)
    vim.fn.delete(path)
end

local function test_reload()
    -- reload without prior load returns error
    reset_config()
    local nil_result, nil_err = config.reload()
    assert_nil(nil_result, "reload without prior load should return nil")
    assert_not_nil(nil_err, "reload without prior load should return error")

    -- load initial config, then modify file on disk
    local path = write_temp_huginn("[plugin]\nissue_dir = original")
    config.load(path, mock_logger())
    assert_equal("original", config.active.plugin.issue_dir)

    vim.fn.writefile(vim.split("[plugin]\nissue_dir = reloaded", "\n"), path)

    -- reload bypasses cache, picks up changes
    local result = config.reload(mock_logger())
    assert_not_nil(result, "reload should return config")
    assert_equal("reloaded", config.active.plugin.issue_dir)

    vim.fn.delete(path)
end

function M.run()
    local runner = TestRunner.new("config")

    runner:test("generate_default_file produces well-formed output", test_generate_default_file)
    runner:test("load rejects invalid paths", test_load_rejects_invalid_paths)
    runner:test("load empty file returns defaults", test_load_empty_file_returns_defaults)
    runner:test("load applies user overrides", test_load_user_overrides)
    runner:test("load unknown section logs warning", test_load_unknown_section_warns)
    runner:test("load unknown key in known section warns", test_load_unknown_key_warns)
    runner:test("load type mismatch keeps default", test_load_type_mismatch_keeps_default)
    runner:test("load range violation keeps default", test_load_range_violation_keeps_default)
    runner:test("load caches by path", test_load_caching)
    runner:test("load invalid color keeps default", test_load_invalid_color_keeps_default)
    runner:test("load valid color override accepted", test_load_valid_color_override)
    runner:test("reload bypasses cache and picks up file changes", test_reload)

    runner:run()
end

return M
