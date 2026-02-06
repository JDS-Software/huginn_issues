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

-- run.lua
-- Minimal test harness for headless Neovim testing
-- Usage (all):    nvim --headless --cmd "set rtp+=." -c "lua require('huginn.tests.run').run_all()"
-- Usage (single): nvim --headless --cmd "set rtp+=." -c "lua require('huginn.tests.run').run('runner')"

local M = {}

-- Test modules to run
local test_modules = {
    "runner_test",
    "context_test",
    "ini_parser_test",
    "config_test",
    "logging_test",
    "setup_test",
    "confirm_test",
    "float_test",
    "issue_filter_test",
    "issue_index_test",
    "log_viewer_test",
    "location_test",
    "issue_test",
    "prompt_test",
    "create_test",
    "annotation_test",
    "issue_window_test",
    "show_window_test",
    "show_test",
    "navigate_test",
    "issue_picker_test",
    "add_and_remove_test",
    "home_window_test",
    "home_test",
    "doctor_test",
}

-- Test statistics
local total_tests = 0
local passed_tests = 0
local failed_tests = 0

-- Use io.write+flush instead of print to prevent nvim_feedkeys from eating newlines
local function println(s)
    io.write(s .. "\n")
    io.flush()
end

-- TestRunner class
local TestRunner = {}
TestRunner.__index = TestRunner

function TestRunner.new(module_name)
    local self = setmetatable({}, TestRunner)
    self.module_name = module_name
    self.tests = {}
    return self
end

function TestRunner:test(name, fn)
    table.insert(self.tests, { name = name, fn = fn })
end

function TestRunner:run()
    println("Running tests for " .. self.module_name)

    for _, test in ipairs(self.tests) do
        total_tests = total_tests + 1

        local start = vim.uv.hrtime()
        local success, err = pcall(test.fn)
        local elapsed_ns = vim.uv.hrtime() - start

        local duration
        if elapsed_ns < 1000 then
            duration = string.format("%dns", elapsed_ns)
        elseif elapsed_ns < 1e6 then
            duration = string.format("%dus", elapsed_ns / 1e3)
        elseif elapsed_ns < 1e9 then
            duration = string.format("%dms", elapsed_ns / 1e6)
        elseif elapsed_ns < 6e10 then
            duration = string.format("%.1fs", elapsed_ns / 1e9)
        else
            duration = string.format("%.1fmin", elapsed_ns / 6e10)
        end

        if success then
            passed_tests = passed_tests + 1
            println("  [PASS] " .. test.name .. "... " .. duration)
        else
            failed_tests = failed_tests + 1
            println("  [FAIL] " .. test.name .. "... " .. duration)
            println("    Error: " .. tostring(err))
        end
    end

    println("")
end

-- Assertion helpers
function assert_equal(expected, actual, message)
    if expected ~= actual then
        error(
            string.format(
                "%s\nExpected: %s\nActual: %s",
                message or "Assertion failed",
                vim.inspect(expected),
                vim.inspect(actual)
            )
        )
    end
end

function assert_nil(value, message)
    if value ~= nil then
        error(string.format("%s\nExpected nil but got: %s", message or "Assertion failed", vim.inspect(value)))
    end
end

function assert_not_nil(value, message)
    if value == nil then
        error(message or "Expected non-nil value")
    end
end

function assert_true(value, message)
    if value ~= true then
        error(message or "Expected true")
    end
end

function assert_false(value, message)
    if value ~= false then
        error(message or "Expected false")
    end
end

function assert_match(pattern, str, message)
    if not str or not str:match(pattern) then
        error(string.format("%s\nPattern: %s\nString: %s", message or "Pattern match failed", pattern, tostring(str)))
    end
end

-- Make assertions and TestRunner global for test files
_G.assert_equal = assert_equal
_G.assert_nil = assert_nil
_G.assert_not_nil = assert_not_nil
_G.assert_true = assert_true
_G.assert_false = assert_false
_G.assert_match = assert_match
_G.TestRunner = TestRunner

-- Reset counters and print header
local function preamble()
    total_tests = 0
    passed_tests = 0
    failed_tests = 0

    println("==================")
    println("Huginn Test Suite")
    println("==================")
    println("")
end

-- Print summary and exit with appropriate code
local function epilogue()
    println("==================")
    println("Test Summary")
    println("==================")
    println(string.format("Total:  %d", total_tests))
    println(string.format("Passed: %d", passed_tests))
    println(string.format("Failed: %d", failed_tests))
    println("")

    if failed_tests > 0 then
        vim.cmd("cquit 1")
    else
        vim.cmd("quit")
    end
end

-- Load and run a single test module by name
local function run_module(module_name)
    local ok, test_module = pcall(require, "huginn.tests." .. module_name)
    if ok then
        if test_module and test_module.run then
            test_module.run()
        else
            println("Warning: Test module " .. module_name .. " does not have a run() function")
        end
    else
        println("Failed to load test module: " .. module_name)
        println("  Error: " .. tostring(test_module))
        println("")
    end
end

function M.run_all()
    preamble()
    for _, module_name in ipairs(test_modules) do
        run_module(module_name)
    end
    epilogue()
end

function M.run(target)
    target = target:gsub("_test$", "") .. "_test"
    preamble()
    run_module(target)
    epilogue()
end

return M
