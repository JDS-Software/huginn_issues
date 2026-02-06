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

-- navigate_test.lua
-- Tests for the HuginnNext / HuginnPrevious commands

local M = {}

local navigate = require("huginn.commands.navigate")
local context = require("huginn.modules.context")
local config = require("huginn.modules.config")
local issue = require("huginn.modules.issue")
local issue_index = require("huginn.modules.issue_index")
local location = require("huginn.modules.location")
local filepath = require("huginn.modules.filepath")
local logging = require("huginn.modules.logging")

--- Create a temp project directory with a .huginn file and initialize context
---@param huginn_content string? .huginn file content
---@return string dir absolute path to temp directory
local function setup_project(huginn_content)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local huginn_path = dir .. "/.huginn"
    vim.fn.writefile(vim.split(huginn_content or "", "\n"), huginn_path)

    issue._reset()
    issue_index._clear()
    context._reset()
    config.active = {}
    config.huginn_path = nil

    context.init(dir, logging.new())
    return dir
end

--- Wipe all buffers except the initial unnamed one
local function wipe_buffers()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_set_option_value("modified", false, { buf = buf })
            if vim.api.nvim_buf_get_name(buf) ~= "" then
                vim.api.nvim_buf_delete(buf, { force = true })
            end
        end
    end
end

--- Tear down a temp project
---@param dir string absolute path to temp directory
local function teardown(dir)
    wipe_buffers()
    issue._reset()
    issue_index._clear()
    context._reset()
    config.active = {}
    config.huginn_path = nil
    vim.fn.delete(dir, "rf")
end

--- Create a buffer with the given name and content, set it as current
---@param name string buffer name (absolute path)
---@param lines string[] buffer lines
---@return integer bufnr buffer number
local function create_buffer(name, lines)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, name)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(buf)
    return buf
end

--- Create a mock tree-sitter node that returns the given 0-based start_row from :range()
---@param start_row integer 0-based line number
---@return table node mock node with range() method
local function mock_node(start_row)
    return {
        range = function()
            return start_row, 0, start_row, 0
        end,
    }
end

--- Helper: 10-line buffer content
local ten_lines = { "aaa", "bbb", "ccc", "ddd", "eee", "fff", "ggg", "hhh", "iii", "jjj" }

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

local function test_no_context()
    context._reset()
    config.active = {}
    config.huginn_path = nil

    local err = navigate.execute_next({ range = 0 })
    assert_not_nil(err, "execute_next should return error without context")

    local err2 = navigate.execute_previous({ range = 0 })
    assert_not_nil(err2, "execute_previous should return error without context")
end

local function test_no_issues_for_file()
    local dir = setup_project("")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile(ten_lines, source_path)
    create_buffer(source_path, ten_lines)

    local err = navigate.execute_next({ range = 0 })
    assert_nil(err, "execute_next should not return error when no issues exist")

    teardown(dir)
end

local function test_only_closed_issues()
    local dir = setup_project("")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile(ten_lines, source_path)
    create_buffer(source_path, ten_lines)

    local rel_path = filepath.absolute_to_relative(source_path, dir)
    local loc = { filepath = rel_path, reference = {} }
    local created, create_err = issue.create(loc, "A closeable issue")
    assert_nil(create_err, "issue creation should not error")
    assert_not_nil(created, "issue should be created")

    -- Close the issue via resolve (also updates the index)
    issue.resolve(created.id, "")

    local err = navigate.execute_next({ range = 0 })
    assert_nil(err, "execute_next should not return error with only closed issues")

    teardown(dir)
end

local function test_next_single_file_scoped_issue()
    local dir = setup_project("")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile(ten_lines, source_path)
    create_buffer(source_path, ten_lines)

    local rel_path = filepath.absolute_to_relative(source_path, dir)
    local loc = { filepath = rel_path, reference = {} }
    local _, create_err = issue.create(loc, "File-scoped issue")
    assert_nil(create_err, "issue creation should not error")

    -- Cursor on line 5 (1-based), next should jump to line 1 (file-scoped = line 0, displayed as 1)
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    navigate.execute_next({ range = 0 })
    local cursor = vim.api.nvim_win_get_cursor(0)
    assert_equal(1, cursor[1], "next from line 5 with file-scoped issue should go to line 1")

    teardown(dir)
end

local function test_previous_single_file_scoped_issue()
    local dir = setup_project("")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile(ten_lines, source_path)
    create_buffer(source_path, ten_lines)

    local rel_path = filepath.absolute_to_relative(source_path, dir)
    local loc = { filepath = rel_path, reference = {} }
    local _, create_err = issue.create(loc, "File-scoped issue")
    assert_nil(create_err, "issue creation should not error")

    -- Cursor on line 5, previous should jump to line 1
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    navigate.execute_previous({ range = 0 })
    local cursor = vim.api.nvim_win_get_cursor(0)
    assert_equal(1, cursor[1], "previous from line 5 with file-scoped issue should go to line 1")

    teardown(dir)
end

local function test_next_wraps_single_issue()
    local dir = setup_project("")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile(ten_lines, source_path)
    create_buffer(source_path, ten_lines)

    local rel_path = filepath.absolute_to_relative(source_path, dir)
    local loc = { filepath = rel_path, reference = {} }
    local _, create_err = issue.create(loc, "File-scoped issue")
    assert_nil(create_err, "issue creation should not error")

    -- Cursor already on line 1 (the issue line), next wraps back to line 1
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    navigate.execute_next({ range = 0 })
    local cursor = vim.api.nvim_win_get_cursor(0)
    assert_equal(1, cursor[1], "next from line 1 with single issue should wrap to line 1")

    teardown(dir)
end

local function test_previous_wraps_single_issue()
    local dir = setup_project("")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile(ten_lines, source_path)
    create_buffer(source_path, ten_lines)

    local rel_path = filepath.absolute_to_relative(source_path, dir)
    local loc = { filepath = rel_path, reference = {} }
    local _, create_err = issue.create(loc, "File-scoped issue")
    assert_nil(create_err, "issue creation should not error")

    -- Cursor already on line 1, previous wraps back to line 1
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    navigate.execute_previous({ range = 0 })
    local cursor = vim.api.nvim_win_get_cursor(0)
    assert_equal(1, cursor[1], "previous from line 1 with single issue should wrap to line 1")

    teardown(dir)
end

local function test_next_multiple_lines()
    local dir = setup_project("")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile(ten_lines, source_path)
    create_buffer(source_path, ten_lines)

    local rel_path = filepath.absolute_to_relative(source_path, dir)
    -- Create one issue with three references (will mock resolution to different lines)
    local loc = { filepath = rel_path, reference = { "identifier|foo", "identifier|bar", "identifier|baz" } }
    local _, create_err = issue.create(loc, "Multi-ref issue")
    assert_nil(create_err, "issue creation should not error")

    -- Mock location.resolve to return nodes at lines 2, 5, 8 (0-based)
    local original_resolve = location.resolve
    location.resolve = function()
        return {
            ["identifier|foo"] = { result = "found", node = mock_node(2) },
            ["identifier|bar"] = { result = "found", node = mock_node(5) },
            ["identifier|baz"] = { result = "found", node = mock_node(8) },
        }
    end

    -- Cursor on line 4 (1-based), 0-based: 3. Next line > 3 is 5. Display: line 6
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    navigate.execute_next({ range = 0 })
    local cursor = vim.api.nvim_win_get_cursor(0)
    assert_equal(6, cursor[1], "next from line 4 should jump to line 6 (0-based 5)")

    location.resolve = original_resolve
    teardown(dir)
end

local function test_previous_multiple_lines()
    local dir = setup_project("")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile(ten_lines, source_path)
    create_buffer(source_path, ten_lines)

    local rel_path = filepath.absolute_to_relative(source_path, dir)
    local loc = { filepath = rel_path, reference = { "identifier|foo", "identifier|bar", "identifier|baz" } }
    local _, create_err = issue.create(loc, "Multi-ref issue")
    assert_nil(create_err, "issue creation should not error")

    local original_resolve = location.resolve
    location.resolve = function()
        return {
            ["identifier|foo"] = { result = "found", node = mock_node(2) },
            ["identifier|bar"] = { result = "found", node = mock_node(5) },
            ["identifier|baz"] = { result = "found", node = mock_node(8) },
        }
    end

    -- Cursor on line 7 (1-based), 0-based: 6. Last line < 6 is 5. Display: line 6
    vim.api.nvim_win_set_cursor(0, { 7, 0 })
    navigate.execute_previous({ range = 0 })
    local cursor = vim.api.nvim_win_get_cursor(0)
    assert_equal(6, cursor[1], "previous from line 7 should jump to line 6 (0-based 5)")

    location.resolve = original_resolve
    teardown(dir)
end

local function test_next_wraps_from_last()
    local dir = setup_project("")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile(ten_lines, source_path)
    create_buffer(source_path, ten_lines)

    local rel_path = filepath.absolute_to_relative(source_path, dir)
    local loc = { filepath = rel_path, reference = { "identifier|foo", "identifier|bar", "identifier|baz" } }
    local _, create_err = issue.create(loc, "Multi-ref issue")
    assert_nil(create_err, "issue creation should not error")

    local original_resolve = location.resolve
    location.resolve = function()
        return {
            ["identifier|foo"] = { result = "found", node = mock_node(2) },
            ["identifier|bar"] = { result = "found", node = mock_node(5) },
            ["identifier|baz"] = { result = "found", node = mock_node(8) },
        }
    end

    -- Cursor on line 9 (1-based), 0-based: 8 (the last issue line). No line > 8, wrap to first (2). Display: line 3
    vim.api.nvim_win_set_cursor(0, { 9, 0 })
    navigate.execute_next({ range = 0 })
    local cursor = vim.api.nvim_win_get_cursor(0)
    assert_equal(3, cursor[1], "next from last issue line should wrap to first (line 3)")

    location.resolve = original_resolve
    teardown(dir)
end

local function test_previous_wraps_from_first()
    local dir = setup_project("")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile(ten_lines, source_path)
    create_buffer(source_path, ten_lines)

    local rel_path = filepath.absolute_to_relative(source_path, dir)
    local loc = { filepath = rel_path, reference = { "identifier|foo", "identifier|bar", "identifier|baz" } }
    local _, create_err = issue.create(loc, "Multi-ref issue")
    assert_nil(create_err, "issue creation should not error")

    local original_resolve = location.resolve
    location.resolve = function()
        return {
            ["identifier|foo"] = { result = "found", node = mock_node(2) },
            ["identifier|bar"] = { result = "found", node = mock_node(5) },
            ["identifier|baz"] = { result = "found", node = mock_node(8) },
        }
    end

    -- Cursor on line 3 (1-based), 0-based: 2 (the first issue line). No line < 2, wrap to last (8). Display: line 9
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    navigate.execute_previous({ range = 0 })
    local cursor = vim.api.nvim_win_get_cursor(0)
    assert_equal(9, cursor[1], "previous from first issue line should wrap to last (line 9)")

    location.resolve = original_resolve
    teardown(dir)
end

local function test_deduplication_across_issues()
    local dir = setup_project("")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile(ten_lines, source_path)
    create_buffer(source_path, ten_lines)

    local rel_path = filepath.absolute_to_relative(source_path, dir)

    -- Create first issue with a reference
    local loc1 = { filepath = rel_path, reference = { "identifier|foo" } }
    local created1, err1 = issue.create(loc1, "First issue")
    assert_nil(err1, "first issue creation should not error")
    assert_not_nil(created1, "first issue should be created")

    -- Create second issue with a different reference (but we'll mock both to same line)
    local loc2 = { filepath = rel_path, reference = { "identifier|bar" } }
    local created2, err2 = issue.create(loc2, "Second issue")
    assert_nil(err2, "second issue creation should not error")
    assert_not_nil(created2, "second issue should be created")

    -- Mock both issues to resolve to the same line (0-based: 4) and one unique line (0-based: 7)
    local original_resolve = location.resolve
    location.resolve = function(_, loc)
        if loc.reference[1] == "identifier|foo" then
            return { ["identifier|foo"] = { result = "found", node = mock_node(4) } }
        else
            return { ["identifier|bar"] = { result = "found", node = mock_node(4) } }
        end
    end

    -- Both issues at line 5 (0-based 4). Cursor on line 1. Next should go to line 5.
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    navigate.execute_next({ range = 0 })
    local cursor = vim.api.nvim_win_get_cursor(0)
    assert_equal(5, cursor[1], "next should jump to deduplicated line 5")

    -- Now from line 5, next should wrap to line 5 (only one unique line)
    navigate.execute_next({ range = 0 })
    cursor = vim.api.nvim_win_get_cursor(0)
    assert_equal(5, cursor[1], "next from only issue line should wrap to same line")

    location.resolve = original_resolve
    teardown(dir)
end

function M.run()
    local runner = TestRunner.new("navigate")

    runner:test("no context: returns error", test_no_context)
    runner:test("no issues for file: notifies user", test_no_issues_for_file)
    runner:test("only closed issues: notifies user", test_only_closed_issues)
    runner:test("next with single file-scoped issue jumps to line 1", test_next_single_file_scoped_issue)
    runner:test("previous with single file-scoped issue jumps to line 1", test_previous_single_file_scoped_issue)
    runner:test("next wraps around on single issue", test_next_wraps_single_issue)
    runner:test("previous wraps around on single issue", test_previous_wraps_single_issue)
    runner:test("next jumps to correct line with multiple locations", test_next_multiple_lines)
    runner:test("previous jumps to correct line with multiple locations", test_previous_multiple_lines)
    runner:test("next wraps from last to first", test_next_wraps_from_last)
    runner:test("previous wraps from first to last", test_previous_wraps_from_first)
    runner:test("deduplication: multiple issues on same line", test_deduplication_across_issues)

    runner:run()
end

return M
