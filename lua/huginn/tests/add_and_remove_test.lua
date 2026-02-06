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

-- add_and_remove_test.lua
-- Tests for the HuginnAdd / HuginnRemove commands

local M = {}

local add_and_remove = require("huginn.commands.add_and_remove")
local issue_picker = require("huginn.components.issue_picker")
local context = require("huginn.modules.context")
local config = require("huginn.modules.config")
local issue = require("huginn.modules.issue")
local issue_index = require("huginn.modules.issue_index")
local location = require("huginn.modules.location")
local annotation = require("huginn.modules.annotation")
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
    annotation.setup()
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
    issue_picker._close()
    wipe_buffers()
    annotation._reset()
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
    vim.api.nvim_set_option_value("filetype", "lua", { buf = buf })
    return buf
end

--- Check if tree-sitter is available for Lua in this Neovim environment
---@return boolean
local function has_treesitter_lua()
    local ok, parser = pcall(vim.treesitter.get_parser, 0, "lua")
    return ok and parser ~= nil
end

--- Set up a Lua source buffer with a function and position cursor inside it.
--- Returns the tree-sitter reference for the cursor scope, or nil if tree-sitter
--- is unavailable.
---@param dir string project root
---@return string? cursor_ref tree-sitter reference at cursor, nil when TS unavailable
---@return string rel_path relative filepath
---@return string source_path absolute source filepath
local function setup_source_in_scope(dir)
    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    local lines = { "local function my_func()", "  return 1", "end" }
    vim.fn.writefile(lines, source_path)
    create_buffer(source_path, lines)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    local rel_path = filepath.absolute_to_relative(source_path, dir)

    if not has_treesitter_lua() then
        return nil, rel_path, source_path
    end

    -- Probe tree-sitter for the actual reference at cursor position
    local cmd_ctx = context.from_command({ range = 0 })
    local loc = location.from_context(cmd_ctx)
    assert_true(#loc.reference > 0, "cursor inside function should produce a reference")
    return loc.reference[1], rel_path, source_path
end

local function test_add_no_context()
    issue_picker._close()
    context._reset()
    config.active = {}
    config.huginn_path = nil

    local err = add_and_remove.execute_add({ range = 0 })
    assert_not_nil(err, "execute_add should return error without context")
end

local function test_remove_no_context()
    issue_picker._close()
    context._reset()
    config.active = {}
    config.huginn_path = nil

    local err = add_and_remove.execute_remove({ range = 0 })
    assert_not_nil(err, "execute_remove should return error without context")
end

local function test_cursor_not_in_scope()
    local dir = setup_project("")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    local lines = { "-- top level comment", "", "local function my_func()", "  return 1", "end" }
    vim.fn.writefile(lines, source_path)
    create_buffer(source_path, lines)
    vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- on comment, outside any scope

    if not has_treesitter_lua() then
        teardown(dir)
        return
    end

    -- Create an issue so the "no issues" path is not what stops us
    local rel_path = filepath.absolute_to_relative(source_path, dir)
    local iss = issue.create({ filepath = rel_path, reference = {} }, "file-scoped issue")
    assert_not_nil(iss)

    local add_err = add_and_remove.execute_add({ range = 0 })
    assert_nil(add_err, "add should return nil (alert, not error) outside scope")
    assert_false(issue_picker.is_open(), "add picker should not open outside scope")

    local remove_err = add_and_remove.execute_remove({ range = 0 })
    assert_nil(remove_err, "remove should return nil (alert, not error) outside scope")
    assert_false(issue_picker.is_open(), "remove picker should not open outside scope")

    teardown(dir)
end

local function test_add_filters_and_selects()
    local dir = setup_project("")
    local cursor_ref, rel_path = setup_source_in_scope(dir)

    if not cursor_ref then
        teardown(dir)
        return
    end

    -- Issue A: already has cursor_ref → excluded from picker
    local issue_a = issue.create({ filepath = rel_path, reference = { cursor_ref } }, "Already linked")
    assert_not_nil(issue_a)

    -- Issue B: file-scoped (no references) → eligible per spec
    local issue_b = issue.create({ filepath = rel_path, reference = {} }, "File-scoped")
    assert_not_nil(issue_b)

    local err = add_and_remove.execute_add({ range = 0 })
    assert_nil(err, "execute_add should succeed")
    assert_true(issue_picker.is_open(), "picker should open with eligible issues")

    -- Verify picker filtered correctly: only issue_b (file-scoped, eligible)
    local picker = issue_picker._get_picker()
    assert_not_nil(picker)
    assert_equal(1, #picker.display_issues, "picker should show one eligible issue")
    assert_equal(issue_b.id, picker.display_issues[1].id, "file-scoped issue should be eligible")

    -- Simulate selection → callback adds cursor_ref to issue_b
    picker:select()
    assert_false(issue_picker.is_open(), "picker should close after selection")

    -- Verify the reference was actually added (file-scoped → function-scoped conversion)
    local updated = issue.read(issue_b.id)
    assert_not_nil(updated)
    local found = false
    for _, ref in ipairs(updated.location.reference) do
        if ref == cursor_ref then found = true end
    end
    assert_true(found, "cursor reference should be added to selected issue")

    teardown(dir)
end

local function test_add_all_already_have_ref()
    local dir = setup_project("")
    local cursor_ref, rel_path = setup_source_in_scope(dir)

    if not cursor_ref then
        teardown(dir)
        return
    end

    -- Single issue that already has cursor_ref
    local iss = issue.create({ filepath = rel_path, reference = { cursor_ref } }, "Already has ref")
    assert_not_nil(iss)

    local err = add_and_remove.execute_add({ range = 0 })
    assert_nil(err, "should not error")
    assert_false(issue_picker.is_open(), "picker should not open when all issues have ref")

    teardown(dir)
end

local function test_remove_filters_and_selects()
    local dir = setup_project("")
    local cursor_ref, rel_path = setup_source_in_scope(dir)

    if not cursor_ref then
        teardown(dir)
        return
    end

    -- Issue A: has cursor_ref → eligible for remove
    local issue_a = issue.create({ filepath = rel_path, reference = { cursor_ref } }, "Has ref")
    assert_not_nil(issue_a)

    -- Issue B: file-scoped → never eligible for remove per spec
    local issue_b = issue.create({ filepath = rel_path, reference = {} }, "File-scoped")
    assert_not_nil(issue_b)

    local err = add_and_remove.execute_remove({ range = 0 })
    assert_nil(err, "execute_remove should succeed")
    assert_true(issue_picker.is_open(), "picker should open with eligible issues")

    -- Verify picker filtered correctly: only issue_a (has cursor_ref)
    local picker = issue_picker._get_picker()
    assert_not_nil(picker)
    assert_equal(1, #picker.display_issues, "picker should show one eligible issue")
    assert_equal(issue_a.id, picker.display_issues[1].id, "issue with cursor ref should be eligible")

    -- Simulate selection → callback removes cursor_ref from issue_a
    picker:select()
    assert_false(issue_picker.is_open(), "picker should close after selection")

    -- Verify the reference was removed (function-scoped → file-scoped conversion)
    local updated = issue.read(issue_a.id)
    assert_not_nil(updated)
    assert_equal(0, #updated.location.reference, "reference should be removed, issue now file-scoped")

    teardown(dir)
end

local function test_remove_no_matching_refs()
    local dir = setup_project("")
    local cursor_ref, rel_path = setup_source_in_scope(dir)

    if not cursor_ref then
        teardown(dir)
        return
    end

    -- File-scoped issue — not eligible for remove (no references to match)
    local iss = issue.create({ filepath = rel_path, reference = {} }, "File-scoped")
    assert_not_nil(iss)

    local err = add_and_remove.execute_remove({ range = 0 })
    assert_nil(err, "should not error")
    assert_false(issue_picker.is_open(), "picker should not open when no issues match")

    teardown(dir)
end

function M.run()
    local runner = TestRunner.new("add_and_remove")

    runner:test("add: no context returns error", test_add_no_context)
    runner:test("remove: no context returns error", test_remove_no_context)
    runner:test("cursor not in scope: add and remove abort without picker", test_cursor_not_in_scope)
    runner:test("add: filters out issues with ref, selects file-scoped, adds reference", test_add_filters_and_selects)
    runner:test("add: all issues already have reference, no picker", test_add_all_already_have_ref)
    runner:test("remove: filters to issues with ref, selects and removes reference", test_remove_filters_and_selects)
    runner:test("remove: no issues have matching reference, no picker", test_remove_no_matching_refs)

    runner:run()
end

return M
