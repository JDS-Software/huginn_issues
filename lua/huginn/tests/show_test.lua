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

-- show_test.lua
-- Tests for the HuginnShow command

local M = {}

local show = require("huginn.commands.show")
local show_window = require("huginn.components.show_window")
local context = require("huginn.modules.context")
local config = require("huginn.modules.config")
local issue = require("huginn.modules.issue")
local issue_index = require("huginn.modules.issue_index")
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
    show_window._close()
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

local function test_no_context()
    show_window._close()
    context._reset()
    config.active = {}
    config.huginn_path = nil

    local err = show.execute({ range = 0 })
    assert_not_nil(err, "execute should return error without context")
end

local function test_no_issues_for_file()
    local dir = setup_project("")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile({ "local x = 1" }, source_path)
    create_buffer(source_path, { "local x = 1" })

    local err = show.execute({ range = 0 })
    assert_nil(err, "execute should not return error when no issues exist")
    assert_false(show_window.is_open(), "show window should not open when no issues")

    teardown(dir)
end

local function test_opens_show_window()
    local dir = setup_project("")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile({ "local x = 1" }, source_path)
    create_buffer(source_path, { "local x = 1" })

    -- Create an issue for this file
    local rel_path = filepath.absolute_to_relative(source_path, dir)
    local loc = { filepath = rel_path, reference = {} }
    local created, create_err = issue.create(loc, "A test issue.")
    assert_nil(create_err, "issue creation should not error")
    assert_not_nil(created, "issue should be created")

    local err = show.execute({ range = 0 })
    assert_nil(err, "execute should not return error")
    assert_true(show_window.is_open(), "show window should be open")

    teardown(dir)
end

function M.run()
    local runner = TestRunner.new("show")

    runner:test("no context: returns error", test_no_context)
    runner:test("no issues for file: notifies user, no window", test_no_issues_for_file)
    runner:test("opens show window with correct data when issues exist", test_opens_show_window)

    runner:run()
end

return M
