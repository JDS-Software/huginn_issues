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

-- annotation_test.lua
-- Tests for the annotation module

local M = {}

local annotation = require("huginn.modules.annotation")
local context = require("huginn.modules.context")
local config = require("huginn.modules.config")
local issue_index = require("huginn.modules.issue_index")
local issue = require("huginn.modules.issue")
local location = require("huginn.modules.location")
local filepath = require("huginn.modules.filepath")
local logging = require("huginn.modules.logging")

local ICON = "\xf0\x9f\x90\xa6\xe2\x80\x8d\xe2\xac\x9b"
local DAGGER = "\xe2\x80\xa0"

--- Create a temp project directory with a .huginn file and initialize context
---@param huginn_content string? .huginn file content
---@return string dir absolute path to temp directory
local function setup_project(huginn_content)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local huginn_path = dir .. "/.huginn"
    vim.fn.writefile(vim.split(huginn_content or "", "\n"), huginn_path)

    annotation._reset()
    issue._reset()
    issue_index._clear()
    context._reset()
    config.active = {}
    config.huginn_path = nil

    context.init(dir, logging.new())
    annotation.setup()
    return dir
end

--- Tear down a temp project
---@param dir string absolute path to temp directory
local function teardown(dir)
    annotation._reset()
    issue._reset()
    issue_index._clear()
    context._reset()
    config.active = {}
    config.huginn_path = nil
    vim.fn.delete(dir, "rf")
end

--- Reset module state without filesystem cleanup
local function reset()
    annotation._reset()
    issue._reset()
    issue_index._clear()
    context._reset()
    config.active = {}
    config.huginn_path = nil
end

--- Create a source file on disk and return its absolute path
---@param dir string project root
---@param rel_path string relative path
---@param content string? file content
---@return string abs_path
local function create_source_file(dir, rel_path, content)
    local abs_path = filepath.join(dir, rel_path)
    local parent = filepath.dirname(abs_path)
    vim.fn.mkdir(parent, "p")
    vim.fn.writefile(vim.split(content or "", "\n"), abs_path)
    return abs_path
end

--- Create a buffer for the given file path
---@param abs_path string
---@return integer bufnr
local function create_buffer(abs_path)
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, abs_path)
    local lines = vim.fn.readfile(abs_path)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return bufnr
end

--- Get all extmarks in the huginn namespace for a buffer
---@param bufnr integer
---@return table[] extmarks
local function get_extmarks(bufnr)
    local ns = annotation._get_ns()
    if not ns then return {} end
    return vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
end

--- Create an open issue in the index for a source file (file-scoped, no reference)
---@param source_path string absolute path to source file
---@param issue_id string
---@param description string?
local function create_file_scoped_issue(source_path, issue_id, description)
    local ctx = context.get()
    local rel_path = filepath.absolute_to_relative(source_path, ctx.cwd)
    local loc = { filepath = rel_path, reference = {} }

    -- Build and write the issue
    local iss = {
        id = issue_id,
        version = 1,
        status = "OPEN",
        location = loc,
        blocks = {},
        mtime = 0,
    }
    if description and description ~= "" then
        iss.blocks["Issue Description"] = description
    end
    issue.write(iss)
    issue_index.create(rel_path, issue_id)
end

--- Create a closed issue in the index for a source file
---@param source_path string absolute path to source file
---@param issue_id string
local function create_closed_issue(source_path, issue_id)
    local ctx = context.get()
    local rel_path = filepath.absolute_to_relative(source_path, ctx.cwd)
    local loc = { filepath = rel_path, reference = {} }

    local iss = {
        id = issue_id,
        version = 1,
        status = "CLOSED",
        location = loc,
        blocks = {},
        mtime = 0,
    }
    issue.write(iss)
    issue_index.create(rel_path, issue_id)
    issue_index.close(rel_path, issue_id)
    issue_index.flush()
end


local function test_annotate_no_context()
    reset()
    -- Should not error even without context
    annotation.setup()
    local bufnr = vim.api.nvim_create_buf(true, false)
    annotation.annotate(bufnr)
    local marks = get_extmarks(bufnr)
    assert_equal(0, #marks, "no extmarks without context")
    vim.api.nvim_buf_delete(bufnr, { force = true })
    annotation._reset()
end

local function test_annotate_no_issues()
    local dir = setup_project("")
    local source = create_source_file(dir, "src/main.lua", "print('hello')")
    local bufnr = create_buffer(source)

    annotation.annotate(bufnr)
    local marks = get_extmarks(bufnr)
    assert_equal(0, #marks, "no extmarks when file has no index entry")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    teardown(dir)
end

local function test_annotate_file_scoped()
    local dir = setup_project("")
    local source = create_source_file(dir, "src/main.lua", "print('hello')")
    local bufnr = create_buffer(source)

    create_file_scoped_issue(source, "20260110_120000", "test issue")

    annotation.annotate(bufnr)
    local marks = get_extmarks(bufnr)
    assert_equal(1, #marks, "should have one extmark")
    assert_equal(0, marks[1][2], "extmark should be on line 0")

    local details = marks[1][4]
    assert_not_nil(details.virt_text, "extmark should have virt_text")
    local text = details.virt_text[1][1]
    assert_match("%(1%)", text, "should show count (1)")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    teardown(dir)
end

local function test_annotate_multiple_open()
    local dir = setup_project("")
    local source = create_source_file(dir, "src/main.lua", "print('hello')")
    local bufnr = create_buffer(source)

    create_file_scoped_issue(source, "20260110_120000", "issue one")
    create_file_scoped_issue(source, "20260110_120001", "issue two")

    annotation.annotate(bufnr)
    local marks = get_extmarks(bufnr)
    assert_equal(1, #marks, "should have one extmark for file-scoped")
    local text = marks[1][4].virt_text[1][1]
    assert_match("%(2%)", text, "should show count (2)")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    teardown(dir)
end

local function test_all_closed_dagger()
    local dir = setup_project("")
    local source = create_source_file(dir, "src/main.lua", "print('hello')")
    local bufnr = create_buffer(source)

    create_closed_issue(source, "20260110_120000")

    annotation.annotate(bufnr)
    local marks = get_extmarks(bufnr)
    assert_equal(1, #marks, "should have one extmark for dagger")
    assert_equal(0, marks[1][2], "dagger should be on line 0")

    local text = marks[1][4].virt_text[1][1]
    assert_match(DAGGER, text, "should show dagger marker")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    teardown(dir)
end

local function test_closed_excluded_from_count()
    local dir = setup_project("")
    local source = create_source_file(dir, "src/main.lua", "print('hello')")
    local bufnr = create_buffer(source)

    create_file_scoped_issue(source, "20260110_120000", "open issue")
    create_closed_issue(source, "20260110_120001")

    annotation.annotate(bufnr)
    local marks = get_extmarks(bufnr)
    assert_equal(1, #marks, "should have one extmark")
    local text = marks[1][4].virt_text[1][1]
    assert_match("%(1%)", text, "should show count (1), not (2)")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    teardown(dir)
end

local function test_clear()
    local dir = setup_project("")
    local source = create_source_file(dir, "src/main.lua", "print('hello')")
    local bufnr = create_buffer(source)

    create_file_scoped_issue(source, "20260110_120000", "test issue")

    annotation.annotate(bufnr)
    local marks = get_extmarks(bufnr)
    assert_equal(1, #marks, "should have extmark before clear")

    annotation.clear(bufnr)
    marks = get_extmarks(bufnr)
    assert_equal(0, #marks, "should have no extmarks after clear")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    teardown(dir)
end

local function test_scratch_buffer()
    local dir = setup_project("")
    local bufnr = vim.api.nvim_create_buf(true, true)
    -- Scratch buffer has no name
    annotation.annotate(bufnr)
    local marks = get_extmarks(bufnr)
    assert_equal(0, #marks, "no extmarks on scratch buffer")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    teardown(dir)
end

local function test_disabled_via_config()
    local dir = setup_project("[annotation]\nenabled = false")
    local source = create_source_file(dir, "src/main.lua", "print('hello')")
    local bufnr = create_buffer(source)

    create_file_scoped_issue(source, "20260110_120000", "test issue")

    annotation.annotate(bufnr)
    local marks = get_extmarks(bufnr)
    assert_equal(0, #marks, "no extmarks when annotation disabled")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    teardown(dir)
end

--- Check if tree-sitter is available for Lua in this Neovim environment
---@return boolean
local function has_treesitter_lua()
    local ok, parser = pcall(vim.treesitter.get_parser, 0, "lua")
    return ok and parser ~= nil
end

local function test_function_scoped_resolves_to_line()
    local dir = setup_project("")
    local content = table.concat({
        "local function foo()",
        "  return 1",
        "end",
        "",
        "local function bar()",
        "  return 2",
        "end",
    }, "\n")
    local source = create_source_file(dir, "src/main.lua", content)
    local bufnr = create_buffer(source)
    vim.api.nvim_set_option_value("filetype", "lua", { buf = bufnr })
    vim.api.nvim_set_current_buf(bufnr)

    if not has_treesitter_lua() then
        vim.api.nvim_buf_delete(bufnr, { force = true })
        teardown(dir)
        return
    end

    local rel_path = filepath.absolute_to_relative(source, dir)

    -- Probe tree-sitter for the reference at each function
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local cmd_ctx = context.from_command({ range = 0 })
    local loc = location.from_context(cmd_ctx)
    assert_true(#loc.reference > 0, "cursor inside foo should produce a reference")
    local foo_ref = loc.reference[1]

    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    cmd_ctx = context.from_command({ range = 0 })
    loc = location.from_context(cmd_ctx)
    assert_true(#loc.reference > 0, "cursor inside bar should produce a reference")
    local bar_ref = loc.reference[1]

    -- Create function-scoped issues
    local iss_foo = issue.create({ filepath = rel_path, reference = { foo_ref } }, "Issue on foo")
    assert_not_nil(iss_foo)
    local iss_bar = issue.create({ filepath = rel_path, reference = { bar_ref } }, "Issue on bar")
    assert_not_nil(iss_bar)

    annotation.annotate(bufnr)
    local marks = get_extmarks(bufnr)

    assert_equal(2, #marks, "should have two extmarks for two functions")
    table.sort(marks, function(a, b) return a[2] < b[2] end)
    assert_equal(0, marks[1][2], "foo extmark should be at line 0")
    assert_match("%(1%)", marks[1][4].virt_text[1][1], "foo should show count (1)")
    assert_equal(4, marks[2][2], "bar extmark should be at line 4")
    assert_match("%(1%)", marks[2][4].virt_text[1][1], "bar should show count (1)")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    teardown(dir)
end

local function test_unresolvable_ref_omitted()
    local dir = setup_project("")
    local content = "local function foo()\n  return 1\nend"
    local source = create_source_file(dir, "src/main.lua", content)
    local bufnr = create_buffer(source)
    vim.api.nvim_set_option_value("filetype", "lua", { buf = bufnr })
    vim.api.nvim_set_current_buf(bufnr)

    if not has_treesitter_lua() then
        vim.api.nvim_buf_delete(bufnr, { force = true })
        teardown(dir)
        return
    end

    local rel_path = filepath.absolute_to_relative(source, dir)

    -- Create issue referencing a function that does not exist in the buffer
    local iss = issue.create(
        { filepath = rel_path, reference = { "function_declaration|nonexistent" } },
        "Bad ref"
    )
    assert_not_nil(iss)

    annotation.annotate(bufnr)
    local marks = get_extmarks(bufnr)

    assert_equal(0, #marks, "unresolvable scoped ref should produce no extmark")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    teardown(dir)
end

local function test_function_scoped_closed_resolves_to_line()
    local dir = setup_project("")
    local content = table.concat({
        "local function foo()",
        "  return 1",
        "end",
        "",
        "local function bar()",
        "  return 2",
        "end",
    }, "\n")
    local source = create_source_file(dir, "src/main.lua", content)
    local bufnr = create_buffer(source)
    vim.api.nvim_set_option_value("filetype", "lua", { buf = bufnr })
    vim.api.nvim_set_current_buf(bufnr)

    if not has_treesitter_lua() then
        vim.api.nvim_buf_delete(bufnr, { force = true })
        teardown(dir)
        return
    end

    local rel_path = filepath.absolute_to_relative(source, dir)

    -- Get the reference for bar (line 5)
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    local cmd_ctx = context.from_command({ range = 0 })
    local loc = location.from_context(cmd_ctx)
    assert_true(#loc.reference > 0, "cursor inside bar should produce a reference")
    local bar_ref = loc.reference[1]

    -- Create and close a function-scoped issue on bar
    local iss = issue.create({ filepath = rel_path, reference = { bar_ref } }, "Closed on bar")
    assert_not_nil(iss)
    issue.resolve(iss.id)
    issue_index.flush()

    annotation.annotate(bufnr)
    local marks = get_extmarks(bufnr)

    assert_equal(1, #marks, "should have one extmark for closed issue")
    assert_equal(4, marks[1][2], "dagger should be on bar's line (4), not line 0")
    assert_match(DAGGER, marks[1][4].virt_text[1][1], "should show dagger marker")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    teardown(dir)
end

local function test_mixed_open_and_closed_different_scopes()
    local dir = setup_project("")
    local content = table.concat({
        "local function foo()",
        "  return 1",
        "end",
        "",
        "local function bar()",
        "  return 2",
        "end",
    }, "\n")
    local source = create_source_file(dir, "src/main.lua", content)
    local bufnr = create_buffer(source)
    vim.api.nvim_set_option_value("filetype", "lua", { buf = bufnr })
    vim.api.nvim_set_current_buf(bufnr)

    if not has_treesitter_lua() then
        vim.api.nvim_buf_delete(bufnr, { force = true })
        teardown(dir)
        return
    end

    local rel_path = filepath.absolute_to_relative(source, dir)

    -- Get references for foo and bar
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local cmd_ctx = context.from_command({ range = 0 })
    local loc = location.from_context(cmd_ctx)
    local foo_ref = loc.reference[1]

    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    cmd_ctx = context.from_command({ range = 0 })
    loc = location.from_context(cmd_ctx)
    local bar_ref = loc.reference[1]

    -- Open issue on foo
    local iss_foo = issue.create({ filepath = rel_path, reference = { foo_ref } }, "Open on foo")
    assert_not_nil(iss_foo)

    -- Closed issue on bar
    local iss_bar = issue.create({ filepath = rel_path, reference = { bar_ref } }, "Closed on bar")
    assert_not_nil(iss_bar)
    issue.resolve(iss_bar.id)
    issue_index.flush()

    annotation.annotate(bufnr)
    local marks = get_extmarks(bufnr)

    assert_equal(2, #marks, "should have two extmarks: open on foo, dagger on bar")
    table.sort(marks, function(a, b) return a[2] < b[2] end)
    assert_equal(0, marks[1][2], "foo extmark should be at line 0")
    assert_match("%(1%)", marks[1][4].virt_text[1][1], "foo should show open count (1)")
    assert_equal(4, marks[2][2], "bar extmark should be at line 4")
    assert_match(DAGGER, marks[2][4].virt_text[1][1], "bar should show dagger")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    teardown(dir)
end

local function test_delete_function_clears_annotation()
    local dir = setup_project("")
    local content = table.concat({
        "local function foo()",
        "  return 1",
        "end",
        "",
        "local function bar()",
        "  return 2",
        "end",
    }, "\n")
    local source = create_source_file(dir, "src/main.lua", content)
    local bufnr = create_buffer(source)
    vim.api.nvim_set_option_value("filetype", "lua", { buf = bufnr })
    vim.api.nvim_set_current_buf(bufnr)

    if not has_treesitter_lua() then
        vim.api.nvim_buf_delete(bufnr, { force = true })
        teardown(dir)
        return
    end

    local rel_path = filepath.absolute_to_relative(source, dir)

    -- Get reference for foo (line 1)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local cmd_ctx = context.from_command({ range = 0 })
    local loc = location.from_context(cmd_ctx)
    assert_true(#loc.reference > 0, "cursor inside foo should produce a reference")
    local foo_ref = loc.reference[1]

    -- Create a function-scoped issue on foo
    local iss = issue.create({ filepath = rel_path, reference = { foo_ref } }, "Issue on foo")
    assert_not_nil(iss)

    -- Annotate: should show extmark on foo's line
    annotation.annotate(bufnr)
    local marks = get_extmarks(bufnr)
    assert_equal(1, #marks, "should have one extmark on foo")
    assert_equal(0, marks[1][2], "foo extmark should be at line 0")

    -- Delete foo (lines 0-2) — simulates visual-mode delete
    vim.api.nvim_buf_set_lines(bufnr, 0, 3, false, {})

    -- Re-annotate: foo is gone, annotation should disappear
    annotation.annotate(bufnr)
    marks = get_extmarks(bufnr)
    assert_equal(0, #marks, "annotation should disappear when function is deleted")

    -- Re-insert foo at the top — simulates paste
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, {
        "local function foo()",
        "  return 1",
        "end",
    })

    -- Re-annotate: foo is back, annotation should reappear
    annotation.annotate(bufnr)
    marks = get_extmarks(bufnr)
    assert_equal(1, #marks, "annotation should reappear when function is pasted back")
    assert_equal(0, marks[1][2], "foo extmark should be at line 0 after re-insert")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    teardown(dir)
end

local function test_cache_hit_skips_reannotation()
    local dir = setup_project("")
    local source = create_source_file(dir, "src/main.lua", "print('hello')")
    local bufnr = create_buffer(source)

    create_file_scoped_issue(source, "20260110_120000", "test issue")

    annotation.annotate(bufnr)
    local marks1 = get_extmarks(bufnr)
    assert_equal(1, #marks1, "first annotate should place one extmark")

    -- Manually wipe extmarks without evicting cache
    local ns_id = annotation._get_ns()
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    local cleared = get_extmarks(bufnr)
    assert_equal(0, #cleared, "extmarks should be gone after manual clear")

    -- Second annotate with no changes should be a cache hit (returns early)
    annotation.annotate(bufnr)
    local marks2 = get_extmarks(bufnr)
    assert_equal(0, #marks2, "cache hit should skip re-annotation, extmarks stay cleared")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    teardown(dir)
end

local function test_cache_invalidation_on_content_change()
    local dir = setup_project("")
    local source = create_source_file(dir, "src/main.lua", "print('hello')")
    local bufnr = create_buffer(source)

    create_file_scoped_issue(source, "20260110_120000", "test issue")

    annotation.annotate(bufnr)
    local marks1 = get_extmarks(bufnr)
    assert_equal(1, #marks1, "first annotate should place one extmark")

    -- Modify buffer content (bumps changedtick)
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "-- new comment" })

    -- Manually wipe extmarks without evicting cache
    local ns_id = annotation._get_ns()
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    local cleared = get_extmarks(bufnr)
    assert_equal(0, #cleared, "extmarks should be gone after manual clear")

    -- annotate should detect stale changedtick and re-place extmarks
    annotation.annotate(bufnr)
    local marks2 = get_extmarks(bufnr)
    assert_equal(1, #marks2, "cache miss should re-create extmarks after content change")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    teardown(dir)
end

local function test_cache_invalidation_on_issue_change()
    local dir = setup_project("")
    local source = create_source_file(dir, "src/main.lua", "print('hello')")
    local bufnr = create_buffer(source)

    create_file_scoped_issue(source, "20260110_120000", "first issue")

    annotation.annotate(bufnr)
    local marks1 = get_extmarks(bufnr)
    assert_equal(1, #marks1, "first annotate should place one extmark")
    local text1 = marks1[1][4].virt_text[1][1]
    assert_match("%(1%)", text1, "should show count (1)")

    -- Add a second issue (changes the fingerprint)
    create_file_scoped_issue(source, "20260110_120001", "second issue")

    annotation.annotate(bufnr)
    local marks2 = get_extmarks(bufnr)
    assert_equal(1, #marks2, "should have one extmark (both file-scoped)")
    local text2 = marks2[1][4].virt_text[1][1]
    assert_match("%(2%)", text2, "should show count (2) after new issue added")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    teardown(dir)
end

local function test_refresh()
    local dir = setup_project("")
    local source = create_source_file(dir, "src/main.lua", "print('hello')")
    local bufnr = create_buffer(source)
    -- Make it the current buffer
    vim.api.nvim_set_current_buf(bufnr)

    create_file_scoped_issue(source, "20260110_120000", "test issue")

    annotation.refresh()
    local marks = get_extmarks(bufnr)
    assert_equal(1, #marks, "refresh should annotate current buffer")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    teardown(dir)
end

function M.run()
    local runner = TestRunner.new("annotation")

    runner:test("annotate: no error when context uninitialized", test_annotate_no_context)
    runner:test("annotate: no extmarks when file has no index entry", test_annotate_no_issues)
    runner:test("annotate: file-scoped open issue shows count at line 0", test_annotate_file_scoped)
    runner:test("annotate: multiple open issues show aggregate count", test_annotate_multiple_open)
    runner:test("annotate: all closed shows dagger marker", test_all_closed_dagger)
    runner:test("annotate: closed issues excluded from open count", test_closed_excluded_from_count)
    runner:test("clear: removes extmarks", test_clear)
    runner:test("annotate: no error on scratch buffer", test_scratch_buffer)
    runner:test("annotate: disabled via config suppresses extmarks", test_disabled_via_config)
    runner:test("annotate: function-scoped issues resolve to correct lines", test_function_scoped_resolves_to_line)
    runner:test("annotate: unresolvable scoped reference produces no extmark", test_unresolvable_ref_omitted)
    runner:test("annotate: function-scoped closed issue resolves to correct line", test_function_scoped_closed_resolves_to_line)
    runner:test("annotate: mixed open and closed at different scopes", test_mixed_open_and_closed_different_scopes)
    runner:test("annotate: deleting function removes annotation, reinserting restores it", test_delete_function_clears_annotation)
    runner:test("cache: repeated annotate is no-op when unchanged", test_cache_hit_skips_reannotation)
    runner:test("cache: invalidates on buffer content change", test_cache_invalidation_on_content_change)
    runner:test("cache: invalidates on issue set change", test_cache_invalidation_on_issue_change)
    runner:test("refresh: annotates current buffer", test_refresh)

    runner:run()
end

return M
