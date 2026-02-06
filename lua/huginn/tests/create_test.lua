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

-- create_test.lua
-- Tests for the HuginnCreate command

local M = {}

local create = require("huginn.commands.create")
local context = require("huginn.modules.context")
local config = require("huginn.modules.config")
local issue = require("huginn.modules.issue")
local issue_index = require("huginn.modules.issue_index")
local filepath = require("huginn.modules.filepath")
local logging = require("huginn.modules.logging")
local prompt = require("huginn.components.prompt")

-- Store original prompt.show so we can restore it
local original_prompt_show = prompt.show

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
    prompt.show = original_prompt_show
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
    -- Without initializing context, execute should return error
    context._reset()
    config.active = {}
    config.huginn_path = nil

    local prompt_called = false
    prompt.show = function(_, callback)
        prompt_called = true
        callback("test")
    end

    local err = create.execute({ range = 0 })
    assert_not_nil(err, "execute should return error without context")
    assert_false(prompt_called, "prompt should not be shown without context")

    prompt.show = original_prompt_show
end

local function test_normal_mode_create()
    local dir = setup_project("")

    -- Create a source file and buffer
    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile({ "local x = 1" }, source_path)
    create_buffer(source_path, { "local x = 1" })

    -- Mock prompt to auto-submit a description
    prompt.show = function(_, callback)
        callback("Something is broken")
    end

    -- Execute in normal mode
    local err = create.execute({ range = 0 })
    assert_nil(err, "execute should not return error")

    -- Verify issue was created on disk
    -- Find the issue by scanning the issue directory
    local issue_dir = filepath.join(dir, "issues")
    assert_true(filepath.is_directory(issue_dir), "issues directory should exist")

    -- Verify index entry was created
    local rel_path = filepath.absolute_to_relative(source_path, context.get().cwd)
    local entry = issue_index.get(rel_path)
    assert_not_nil(entry, "index entry should exist for source file")

    teardown(dir)
end

local function test_empty_description()
    local dir = setup_project("")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile({ "local x = 1" }, source_path)
    create_buffer(source_path, { "local x = 1" })

    -- Mock prompt to submit empty string
    local created_id = nil
    prompt.show = function(_, callback)
        callback("")
    end

    local err = create.execute({ range = 0 })
    assert_nil(err, "execute with empty description should not return error")

    -- Find the created issue via index
    local rel_path = filepath.absolute_to_relative(source_path, context.get().cwd)
    local entry = issue_index.get(rel_path)
    assert_not_nil(entry, "index entry should exist")

    -- Get the issue ID from the index
    for id, status in pairs(entry.issues) do
        created_id = id
    end
    assert_not_nil(created_id, "should have a created issue ID")

    -- Read issue and verify no description block
    local created_issue = issue.read(created_id)
    assert_not_nil(created_issue, "issue should be readable")
    assert_nil(created_issue.blocks["Issue Description"],
        "empty description should not create description block")

    teardown(dir)
end

local function test_prompt_dismissed()
    local dir = setup_project("")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile({ "local x = 1" }, source_path)
    create_buffer(source_path, { "local x = 1" })

    -- Mock prompt to dismiss (callback with nil)
    prompt.show = function(_, callback)
        callback(nil)
    end

    local err = create.execute({ range = 0 })
    assert_nil(err, "execute should not return error on dismiss")

    -- Verify no issue was created
    local issue_dir = filepath.join(dir, "issues")
    assert_false(filepath.is_directory(issue_dir), "issues directory should not exist after dismiss")

    teardown(dir)
end

local function test_file_scoped_fallback()
    local dir = setup_project("")

    -- Create a plain text file (no tree-sitter parser)
    local source_path = filepath.join(dir, "notes.txt")
    vim.fn.writefile({ "Some plain text notes" }, source_path)
    local buf = create_buffer(source_path, { "Some plain text notes" })
    vim.api.nvim_set_option_value("filetype", "text", { buf = buf })

    local created_id = nil
    prompt.show = function(_, callback)
        callback("A note about this file")
    end

    local err = create.execute({ range = 0 })
    assert_nil(err, "execute should not return error for plain text file")

    -- Find created issue via index
    local rel_path = filepath.absolute_to_relative(source_path, context.get().cwd)
    local entry = issue_index.get(rel_path)
    assert_not_nil(entry, "index entry should exist")

    for id, _ in pairs(entry.issues) do
        created_id = id
    end
    assert_not_nil(created_id, "should have created an issue")

    -- Verify it has a file-scoped location (filepath only, no references)
    local created_issue = issue.read(created_id)
    assert_not_nil(created_issue, "issue should be readable")
    assert_not_nil(created_issue.location, "location should be present")
    assert_equal(0, #created_issue.location.reference, "should have no references (file-scoped)")

    teardown(dir)
end

local function test_issue_create_failure()
    local dir = setup_project("")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile({ "local x = 1" }, source_path)
    create_buffer(source_path, { "local x = 1" })

    -- Make issue directory unwritable so issue.write fails
    local issue_dir = filepath.join(dir, "issues")
    vim.fn.mkdir(issue_dir, "p")
    vim.fn.setfperm(issue_dir, "r-xr-xr-x")

    prompt.show = function(_, callback)
        callback("A bug")
    end

    local err = create.execute({ range = 0 })
    assert_nil(err, "execute itself should not return error (failure is inside callback)")

    -- Verify no index entry was created
    local rel_path = filepath.absolute_to_relative(source_path, context.get().cwd)
    local entry = issue_index.get(rel_path)
    assert_nil(entry, "index entry should not exist when issue creation fails")

    -- Restore permissions so teardown can delete
    vim.fn.setfperm(issue_dir, "rwxr-xr-x")
    teardown(dir)
end

local function test_open_after_create_false()
    local dir = setup_project("")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile({ "local x = 1" }, source_path)
    create_buffer(source_path, { "local x = 1" })

    prompt.show = function(_, callback)
        callback("A bug")
    end

    local err = create.execute({ range = 0 })
    assert_nil(err, "execute should not return error")

    -- Current buffer should still be the source file, not Issue.md
    local current_name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    assert_true(not current_name:find("Issue%.md"),
        "Issue.md should not be opened when open_after_create is false")

    teardown(dir)
end

local function test_open_after_create_true()
    local dir = setup_project("[issue]\nopen_after_create = true")

    local source_path = filepath.join(dir, "src/main.lua")
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile({ "local x = 1" }, source_path)
    create_buffer(source_path, { "local x = 1" })

    prompt.show = function(_, callback)
        callback("A bug")
    end

    local err = create.execute({ range = 0 })
    assert_nil(err, "execute should not return error")

    -- Current buffer should be the Issue.md
    local current_name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    assert_match("Issue%.md", current_name,
        "Issue.md should be opened when open_after_create is true")

    teardown(dir)
end

function M.run()
    local runner = TestRunner.new("create")

    runner:test("no context: returns error, no prompt shown", test_no_context)
    runner:test("normal mode: creates issue with description", test_normal_mode_create)
    runner:test("empty description: creates issue with no description block", test_empty_description)
    runner:test("prompt dismissed: no issue created", test_prompt_dismissed)
    runner:test("file-scoped fallback: creates issue with filepath-only location", test_file_scoped_fallback)
    runner:test("issue.create failure: no index entry created", test_issue_create_failure)
    runner:test("open_after_create false: Issue.md not opened", test_open_after_create_false)
    runner:test("open_after_create true: Issue.md opened in editor", test_open_after_create_true)

    runner:run()
end

return M
