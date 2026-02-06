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

-- issue_window_test.lua
-- Tests for the issue_window floating editor component

local M = {}

local issue_window = require("huginn.components.issue_window")
local issue_mod = require("huginn.modules.issue")
local issue_index = require("huginn.modules.issue_index")
local context = require("huginn.modules.context")
local config = require("huginn.modules.config")
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

    issue_mod._reset()
    issue_index._clear()
    context._reset()
    config.active = {}
    config.huginn_path = nil

    context.init(dir, logging.new())
    return dir
end

--- Tear down a temp project
---@param dir string absolute path to temp directory
local function teardown(dir)
    issue_window._close()
    issue_mod._reset()
    issue_index._clear()
    context._reset()
    config.active = {}
    config.huginn_path = nil
    vim.fn.delete(dir, "rf")
end

--- Create an issue in the project and return its ID
---@param dir string project directory
---@param desc string? description text
---@return string issue_id
local function create_test_issue(dir, desc)
    local rel_path = "src/main.lua"
    local source_path = filepath.join(dir, rel_path)
    vim.fn.mkdir(filepath.dirname(source_path), "p")
    vim.fn.writefile({ "local x = 1" }, source_path)

    local loc = { filepath = rel_path, reference = {} }
    local iss, err = issue_mod.create(loc, desc or "A test issue.")
    assert_nil(err, "issue creation should not error")
    assert_not_nil(iss, "issue should be created")
    return iss.id
end

-- ──────────────────────────────────────────────────────────────────────
-- Tests: blocks_to_lines
-- ──────────────────────────────────────────────────────────────────────

local function test_blocks_to_lines_order()
    local blocks = {
        ["Issue Description"] = "The description.",
        ["Reproduction Steps"] = "Step 1\nStep 2",
        ["Issue Resolution"] = "Fixed it.",
        ["Alpha Block"] = "Alpha content.",
    }

    local lines = issue_window._blocks_to_lines(blocks)
    local text = table.concat(lines, "\n")

    -- Issue Description first
    local desc_pos = text:find("## Issue Description")
    assert_not_nil(desc_pos, "Issue Description should be present")

    -- Custom blocks in alphabetical order
    local alpha_pos = text:find("## Alpha Block")
    local repro_pos = text:find("## Reproduction Steps")
    assert_not_nil(alpha_pos, "Alpha Block should be present")
    assert_not_nil(repro_pos, "Reproduction Steps should be present")
    assert_true(alpha_pos < repro_pos, "Alpha Block should come before Reproduction Steps")

    -- Issue Resolution last
    local res_pos = text:find("## Issue Resolution")
    assert_not_nil(res_pos, "Issue Resolution should be present")
    assert_true(res_pos > repro_pos, "Issue Resolution should come after all custom blocks")
end

local function test_blocks_to_lines_omits_missing()
    local blocks = {
        ["Issue Description"] = "Desc only.",
    }

    local lines = issue_window._blocks_to_lines(blocks)
    local text = table.concat(lines, "\n")

    assert_not_nil(text:find("## Issue Description"), "Issue Description should be present")
    assert_nil(text:find("## Issue Resolution"), "Issue Resolution should be absent when not in blocks")
end

-- ──────────────────────────────────────────────────────────────────────
-- Tests: parse_blocks
-- ──────────────────────────────────────────────────────────────────────

local function test_parse_blocks_basic()
    local lines = {
        "## Issue Description",
        "The description text.",
        "",
        "## Issue Resolution",
        "Fixed it.",
    }

    local blocks = issue_window._parse_blocks(lines)

    assert_equal("The description text.", blocks["Issue Description"], "should parse Issue Description")
    assert_equal("Fixed it.", blocks["Issue Resolution"], "should parse Issue Resolution")
end

local function test_parse_blocks_discards_reserved()
    local lines = {
        "## Version",
        "1",
        "## Status",
        "OPEN",
        "## Location",
        "[location]",
        "filepath = src/main.lua",
        "## Issue Description",
        "Real content.",
    }

    local blocks = issue_window._parse_blocks(lines)

    assert_nil(blocks["Version"], "Version should be discarded")
    assert_nil(blocks["Status"], "Status should be discarded")
    assert_nil(blocks["Location"], "Location should be discarded")
    assert_equal("Real content.", blocks["Issue Description"], "Issue Description should be kept")
end

local function test_parse_blocks_discards_content_before_first_header()
    local lines = {
        "Some stray text",
        "more stray text",
        "## Issue Description",
        "Actual content.",
    }

    local blocks = issue_window._parse_blocks(lines)

    assert_equal("Actual content.", blocks["Issue Description"], "should parse the block after the header")
    -- No block for stray text
    local count = 0
    for _ in pairs(blocks) do count = count + 1 end
    assert_equal(1, count, "should only have one block")
end

local function test_parse_blocks_empty_label_ignored()
    local lines = {
        "## ",
        "content under empty label",
        "## Issue Description",
        "Real content.",
    }

    local blocks = issue_window._parse_blocks(lines)

    assert_nil(blocks[""], "empty label should be ignored")
    assert_equal("Real content.", blocks["Issue Description"], "Issue Description should be present")
end

local function test_parse_blocks_trims_blank_lines()
    local lines = {
        "## Issue Description",
        "",
        "The content.",
        "",
        "",
    }

    local blocks = issue_window._parse_blocks(lines)
    assert_equal("The content.", blocks["Issue Description"], "leading/trailing blank lines should be trimmed")
end

-- ──────────────────────────────────────────────────────────────────────
-- Tests: open/close/is_open
-- ──────────────────────────────────────────────────────────────────────

local function test_open_creates_window()
    local dir = setup_project("")
    local id = create_test_issue(dir, "A test issue.")

    issue_window.open(id)
    assert_true(issue_window.is_open(), "issue window should be open after open()")

    local state = issue_window._get_state()
    assert_not_nil(state, "state should exist")
    assert_equal(id, state.issue_id, "state should contain the issue ID")

    teardown(dir)
end

local function test_open_enforces_singleton()
    local dir = setup_project("")
    local id = create_test_issue(dir, "A test issue.")

    issue_window.open(id)
    assert_true(issue_window.is_open(), "window should be open")

    -- Opening again should focus, not create duplicate
    issue_window.open(id)
    assert_true(issue_window.is_open(), "window should still be open")

    teardown(dir)
end

local function test_close_cleans_up()
    local dir = setup_project("")
    local id = create_test_issue(dir, "A test issue.")

    issue_window.open(id)
    assert_true(issue_window.is_open(), "window should be open")

    issue_window.close()
    assert_false(issue_window.is_open(), "window should be closed after close()")
    assert_nil(issue_window._get_state(), "state should be nil after close")

    teardown(dir)
end

local function test_open_populates_buffer_with_blocks()
    local dir = setup_project("")
    local id = create_test_issue(dir, "Test description.")

    issue_window.open(id)
    local state = issue_window._get_state()
    assert_not_nil(state, "state should exist")

    local lines = vim.api.nvim_buf_get_lines(state.buf_id, 0, -1, false)
    local text = table.concat(lines, "\n")

    assert_not_nil(text:find("## Issue Description"), "buffer should contain Issue Description header")
    assert_not_nil(text:find("Test description."), "buffer should contain issue description text")

    teardown(dir)
end

local function test_open_nonexistent_issue_does_not_open()
    local dir = setup_project("")

    issue_window.open("99990101_000000")
    assert_false(issue_window.is_open(), "window should not open for nonexistent issue")

    teardown(dir)
end

local function test_buffer_starts_unmodified()
    local dir = setup_project("")
    local id = create_test_issue(dir, "Test description.")

    issue_window.open(id)
    local state = issue_window._get_state()
    assert_not_nil(state, "state should exist")
    assert_false(vim.bo[state.buf_id].modified, "buffer should start as unmodified")

    teardown(dir)
end

local function test_buffer_filetype_is_markdown()
    local dir = setup_project("")
    local id = create_test_issue(dir, "Test description.")

    issue_window.open(id)
    local state = issue_window._get_state()
    assert_not_nil(state, "state should exist")
    assert_equal("markdown", vim.bo[state.buf_id].filetype, "buffer filetype should be markdown")

    teardown(dir)
end

-- ──────────────────────────────────────────────────────────────────────
-- Tests: round-trip save
-- ──────────────────────────────────────────────────────────────────────

local function test_round_trip_save()
    local dir = setup_project("")
    local id = create_test_issue(dir, "Original description.")

    -- Add a resolution block to the issue
    local iss = issue_mod.read(id)
    assert_not_nil(iss, "issue should be readable")
    iss.blocks["Issue Resolution"] = "Original resolution."
    issue_mod.write(iss)

    issue_window.open(id)
    local state = issue_window._get_state()
    assert_not_nil(state, "state should exist")

    -- Modify the buffer: change description
    local new_lines = {
        "## Issue Description",
        "Updated description.",
        "",
        "## Issue Resolution",
        "Updated resolution.",
    }
    vim.api.nvim_buf_set_lines(state.buf_id, 0, -1, false, new_lines)

    -- Simulate <C-s> by calling the internal save and close sequence
    -- We can't easily trigger keybindings in tests, so test parse_blocks + write directly
    local blocks = issue_window._parse_blocks(new_lines)
    local fresh_iss = issue_mod.read(id)
    assert_not_nil(fresh_iss, "issue should be re-readable")
    fresh_iss.blocks = blocks
    local ok, write_err = issue_mod.write(fresh_iss)
    assert_true(ok, "write should succeed")
    assert_nil(write_err, "write should not error")

    -- Read back and verify
    issue_mod._reset()
    local final_iss = issue_mod.read(id)
    assert_not_nil(final_iss, "issue should be readable after save")
    assert_equal("Updated description.", final_iss.blocks["Issue Description"], "description should be updated")
    assert_equal("Updated resolution.", final_iss.blocks["Issue Resolution"], "resolution should be updated")

    -- Hidden fields should be preserved
    assert_equal("OPEN", final_iss.status, "status should be preserved")

    teardown(dir)
end

function M.run()
    local runner = TestRunner.new("issue_window")

    runner:test("blocks_to_lines: correct display order", test_blocks_to_lines_order)
    runner:test("blocks_to_lines: omits missing blocks", test_blocks_to_lines_omits_missing)
    runner:test("parse_blocks: basic block parsing", test_parse_blocks_basic)
    runner:test("parse_blocks: discards reserved labels", test_parse_blocks_discards_reserved)
    runner:test("parse_blocks: discards content before first header",
        test_parse_blocks_discards_content_before_first_header)
    runner:test("parse_blocks: empty label is ignored", test_parse_blocks_empty_label_ignored)
    runner:test("parse_blocks: trims leading/trailing blank lines", test_parse_blocks_trims_blank_lines)
    runner:test("open() creates a floating window", test_open_creates_window)
    runner:test("open() enforces singleton", test_open_enforces_singleton)
    runner:test("close() cleans up state", test_close_cleans_up)
    runner:test("open() populates buffer with blocks", test_open_populates_buffer_with_blocks)
    runner:test("open() nonexistent issue does not open", test_open_nonexistent_issue_does_not_open)
    runner:test("buffer starts unmodified", test_buffer_starts_unmodified)
    runner:test("buffer filetype is markdown", test_buffer_filetype_is_markdown)
    runner:test("round-trip save preserves content and hidden fields", test_round_trip_save)

    runner:run()
end

return M
