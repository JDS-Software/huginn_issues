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

-- issue_test.lua
-- Tests for the issue module

local M = {}

local issue = require("huginn.modules.issue")
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

    issue._reset()
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
    issue._reset()
    issue_index._clear()
    context._reset()
    config.active = {}
    config.huginn_path = nil
    vim.fn.delete(dir, "rf")
end

local function test_issue_path()
    local dir = setup_project("")

    -- Valid ID produces correct path
    local path, err = issue.issue_path("20260110_143256")
    assert_nil(err, "issue_path should not error for valid ID")
    assert_not_nil(path, "issue_path should return a path")
    assert_match("issues/2026/01/20260110_143256/Issue%.md$", path,
        "path should follow time directory layout")

    -- Different month/year
    path = issue.issue_path("20251203_091500")
    assert_match("issues/2025/12/20251203_091500/Issue%.md$", path,
        "path should use correct year/month")

    -- Invalid ID returns error
    path, err = issue.issue_path("invalid")
    assert_nil(path, "issue_path should return nil for invalid ID")
    assert_not_nil(err, "issue_path should return error for invalid ID")

    -- No context returns error
    context._reset()
    path, err = issue.issue_path("20260110_143256")
    assert_nil(path, "issue_path should return nil without context")
    assert_not_nil(err, "issue_path should error without context")

    teardown(dir)
end

local function test_serialize_deserialize_basic()
    local dir = setup_project("")

    local loc = { filepath = "src/main.lua", reference = { "function_declaration|my_func" } }
    local original = {
        id = "20260110_143256",
        version = 1,
        status = "OPEN",
        location = loc,
        blocks = {
            ["Issue Description"] = "Something is broken.",
        },
        mtime = 0,
    }

    -- Serialize
    local content = issue.serialize(original)
    assert_not_nil(content, "serialize should produce content")
    assert_match("^# 20260110_143256", content, "should start with H1 ID")
    assert_match("## Version", content, "should contain Version block")
    assert_match("## Status", content, "should contain Status block")
    assert_match("OPEN", content, "should contain status value")
    assert_match("## Location", content, "should contain Location block")
    assert_match("src/main.lua", content, "should contain filepath")
    assert_match("function_declaration|my_func", content, "should contain reference")
    assert_match("## Issue Description", content, "should contain description block")
    assert_match("Something is broken%.", content, "should contain description text")

    -- Deserialize
    local deserialized, err = issue.deserialize(content, "20260110_143256")
    assert_nil(err, "deserialize should not error")
    assert_not_nil(deserialized, "deserialize should return issue")

    -- Verify round-trip
    assert_equal("20260110_143256", deserialized.id, "ID should match")
    assert_equal(1, deserialized.version, "version should match")
    assert_equal("OPEN", deserialized.status, "status should match")
    assert_not_nil(deserialized.location, "location should be present")
    assert_equal("src/main.lua", deserialized.location.filepath, "location filepath should match")
    assert_equal(1, #deserialized.location.reference, "should have 1 reference")
    assert_equal("function_declaration|my_func", deserialized.location.reference[1],
        "reference should match")
    assert_equal("Something is broken.", deserialized.blocks["Issue Description"],
        "description should match")

    teardown(dir)
end

local function test_serialize_no_location()
    local dir = setup_project("")

    local original = {
        id = "20260110_143256",
        version = 1,
        status = "CLOSED",
        location = nil,
        blocks = {
            ["Issue Description"] = "File-level issue.",
            ["Issue Resolution"] = "Fixed it.",
        },
        mtime = 0,
    }

    local content = issue.serialize(original)
    -- Should not contain Location block
    assert_true(not content:find("## Location"), "should not contain Location block when nil")
    assert_match("CLOSED", content, "should contain CLOSED status")
    assert_match("## Issue Description", content, "should have description")
    assert_match("## Issue Resolution", content, "should have resolution")

    -- Deserialize back
    local deserialized, err = issue.deserialize(content)
    assert_nil(err, "deserialize should not error")
    assert_equal("CLOSED", deserialized.status, "status should be CLOSED")
    assert_nil(deserialized.location, "location should be nil")
    assert_equal("File-level issue.", deserialized.blocks["Issue Description"],
        "description should match")
    assert_equal("Fixed it.", deserialized.blocks["Issue Resolution"],
        "resolution should match")

    teardown(dir)
end

local function test_serialize_custom_blocks()
    local dir = setup_project("")

    local original = {
        id = "20260110_143256",
        version = 1,
        status = "OPEN",
        location = { filepath = "src/main.lua", reference = {} },
        blocks = {
            ["Issue Description"] = "A bug.",
            ["Custom Block"] = "Custom content here.",
            ["Another Block"] = "More content.",
        },
        mtime = 0,
    }

    local content = issue.serialize(original)

    -- Verify block ordering: Issue Description before custom blocks
    local desc_pos = content:find("## Issue Description")
    local another_pos = content:find("## Another Block")
    local custom_pos = content:find("## Custom Block")
    assert_not_nil(desc_pos, "should contain Issue Description")
    assert_not_nil(another_pos, "should contain Another Block")
    assert_not_nil(custom_pos, "should contain Custom Block")
    assert_true(desc_pos < another_pos, "Issue Description should come before custom blocks")
    -- Custom blocks are alphabetical: Another Block < Custom Block
    assert_true(another_pos < custom_pos, "Custom blocks should be alphabetical")

    -- Round-trip
    local deserialized = issue.deserialize(content)
    assert_equal("A bug.", deserialized.blocks["Issue Description"])
    assert_equal("Custom content here.", deserialized.blocks["Custom Block"])
    assert_equal("More content.", deserialized.blocks["Another Block"])

    teardown(dir)
end

local function test_serialize_multiple_references()
    local dir = setup_project("")

    local original = {
        id = "20260110_143256",
        version = 1,
        status = "OPEN",
        location = {
            filepath = "src/main.lua",
            reference = {
                "function_declaration|foo",
                "method_definition|bar",
                "class_definition|MyClass",
            },
        },
        blocks = {},
        mtime = 0,
    }

    local content = issue.serialize(original)
    local deserialized = issue.deserialize(content)

    assert_not_nil(deserialized.location, "location should be present")
    assert_equal(3, #deserialized.location.reference, "should have 3 references")
    assert_equal("function_declaration|foo", deserialized.location.reference[1])
    assert_equal("method_definition|bar", deserialized.location.reference[2])
    assert_equal("class_definition|MyClass", deserialized.location.reference[3])

    teardown(dir)
end

local function test_deserialize_error_recovery()
    local dir = setup_project("")

    -- Missing H1: recover from dir_name
    local no_h1 = "## Version\n1\n\n## Status\nOPEN\n"
    local recovered, err = issue.deserialize(no_h1, "20260110_143256")
    assert_nil(err, "should recover from missing H1")
    assert_equal("20260110_143256", recovered.id, "should use dir_name as ID")

    -- Missing H1 with no dir_name: error
    recovered, err = issue.deserialize(no_h1)
    assert_nil(recovered, "should fail without H1 and no dir_name")
    assert_not_nil(err, "should return error")

    -- Missing H1 with invalid dir_name: error
    recovered, err = issue.deserialize(no_h1, "not_a_valid_id")
    assert_nil(recovered, "should fail with invalid dir_name")

    -- Duplicate H2 labels: last-in wins
    local dup_h2 = "# 20260110_143256\n\n## Status\nOPEN\n\n## Status\nCLOSED\n"
    local dup_issue = issue.deserialize(dup_h2)
    assert_equal("CLOSED", dup_issue.status, "duplicate H2 should use last-in-wins")

    -- Unparseable Location: fallback to nil location
    local bad_loc = "# 20260110_143256\n\n## Version\n1\n\n## Status\nOPEN\n\n## Location\nthis is not ini format\n"
    local bad_issue = issue.deserialize(bad_loc)
    assert_not_nil(bad_issue, "should still parse with bad location")
    assert_nil(bad_issue.location, "unparseable location should result in nil")

    -- Missing Version defaults to current
    local no_ver = "# 20260110_143256\n\n## Status\nOPEN\n"
    local no_ver_issue = issue.deserialize(no_ver)
    assert_equal(1, no_ver_issue.version, "missing version should default to 1")

    -- Missing Status defaults to OPEN
    local no_status = "# 20260110_143256\n\n## Version\n1\n"
    local no_status_issue = issue.deserialize(no_status)
    assert_equal("OPEN", no_status_issue.status, "missing status should default to OPEN")

    teardown(dir)
end

local function test_create_and_read()
    local dir = setup_project("")

    local loc = { filepath = "src/main.lua", reference = { "function_declaration|my_func" } }

    -- Create
    local created, err = issue.create(loc, "Something broke.")
    assert_nil(err, "create should not error")
    assert_not_nil(created, "create should return issue")
    assert_equal("OPEN", created.status, "new issue should be OPEN")
    assert_equal(1, created.version, "version should be 1")
    assert_equal("Something broke.", created.blocks["Issue Description"],
        "description should be set")
    assert_not_nil(created.location, "location should be set")
    assert_equal("src/main.lua", created.location.filepath, "location filepath should match")

    -- Verify on disk
    local issue_path = issue.issue_path(created.id)
    assert_true(filepath.exists(issue_path), "Issue.md should exist on disk")

    -- Verify index entry
    local entry = issue_index.get("src/main.lua")
    assert_not_nil(entry, "index entry should exist")
    assert_equal("open", entry.issues[created.id], "index should have open status")

    -- Read from cache
    local cached, read_err = issue.read(created.id)
    assert_nil(read_err, "read should not error")
    assert_equal(created.id, cached.id, "cached ID should match")
    assert_equal("OPEN", cached.status, "cached status should match")

    -- Read from disk (after cache clear)
    issue._reset()
    local from_disk, disk_err = issue.read(created.id)
    assert_nil(disk_err, "read from disk should not error")
    assert_equal(created.id, from_disk.id, "disk ID should match")
    assert_equal("OPEN", from_disk.status, "disk status should match")
    assert_equal("Something broke.", from_disk.blocks["Issue Description"],
        "disk description should match")

    -- Read non-existent issue
    local missing, missing_err = issue.read("20250101_000000")
    assert_nil(missing, "read non-existent should return nil")
    assert_not_nil(missing_err, "read non-existent should return error")

    teardown(dir)
end

local function test_create_empty_description()
    local dir = setup_project("")

    local loc = { filepath = "src/main.lua", reference = {} }

    -- Create with empty description
    local created, err = issue.create(loc, "")
    assert_nil(err, "create with empty description should not error")
    assert_nil(created.blocks["Issue Description"],
        "empty description should not create block")

    teardown(dir)
end

local function test_close_and_reopen()
    local dir = setup_project("")

    local loc = { filepath = "src/main.lua", reference = {} }

    local created, _ = issue.create(loc, "A bug.")
    local id = created.id

    -- Close via resolve
    local closed, err = issue.resolve(id, "Closing.")
    assert_nil(err, "resolve should not error")
    assert_equal("CLOSED", closed.status, "resolved issue should have CLOSED status")

    -- Verify persisted
    issue._reset()
    local reread = issue.read(id)
    assert_equal("CLOSED", reread.status, "closed status should persist")

    -- Verify index updated (flush lazy close first)
    issue_index.flush()
    issue_index._clear()
    local entry = issue_index.get("src/main.lua")
    assert_equal("closed", entry.issues[id], "index should reflect closed status")

    -- Reopen
    local reopened, reopen_err = issue.reopen(id)
    assert_nil(reopen_err, "reopen should not error")
    assert_equal("OPEN", reopened.status, "reopened issue should be OPEN")

    -- Verify index updated
    issue_index.flush()
    issue_index._clear()
    entry = issue_index.get("src/main.lua")
    assert_equal("open", entry.issues[id], "index should reflect open status after reopen")

    teardown(dir)
end

local function test_relocate()
    local dir = setup_project("")

    local loc = { filepath = "src/main.lua", reference = { "function_declaration|my_func" } }

    local created, _ = issue.create(loc, "A bug.")
    local id = created.id

    -- Relocate to new file
    local relocated, err = issue.relocate(id, "src/new_main.lua")
    assert_nil(err, "relocate should not error")
    assert_equal("src/new_main.lua", relocated.location.filepath, "filepath should be updated")
    -- References should be preserved
    assert_equal(1, #relocated.location.reference, "references should be preserved")
    assert_equal("function_declaration|my_func", relocated.location.reference[1],
        "reference should match")

    -- Verify old index entry removed
    local old_entry = issue_index.get("src/main.lua")
    if old_entry then
        assert_false(old_entry:has(id), "old index entry should not have the issue")
    end

    -- Verify new index entry exists
    local new_entry = issue_index.get("src/new_main.lua")
    assert_not_nil(new_entry, "new index entry should exist")
    assert_true(new_entry:has(id), "new index entry should have the issue")

    -- Verify persisted
    issue._reset()
    local reread = issue.read(id)
    assert_equal("src/new_main.lua", reread.location.filepath,
        "relocated filepath should persist")

    teardown(dir)
end

local function test_relocate_closed_issue()
    local dir = setup_project("")

    local loc = { filepath = "src/main.lua", reference = {} }

    local created, _ = issue.create(loc, "A bug.")
    local id = created.id
    issue.resolve(id, "Closing before relocate.")
    issue_index.flush()

    -- Relocate closed issue
    local relocated, err = issue.relocate(id, "src/moved.lua")
    assert_nil(err, "relocate closed issue should not error")
    assert_equal("CLOSED", relocated.status, "status should remain CLOSED")

    -- New index entry should reflect closed status (after flush)
    issue_index.flush()
    issue_index._clear()
    local new_entry = issue_index.get("src/moved.lua")
    assert_not_nil(new_entry, "new index entry should exist")
    assert_equal("closed", new_entry.issues[id], "new entry should be closed")

    teardown(dir)
end

local function test_references()
    local dir = setup_project("")

    local loc = { filepath = "src/main.lua", reference = { "function_declaration|foo" } }

    local created, _ = issue.create(loc, "A bug.")
    local id = created.id

    -- Add reference
    local added, err = issue.add_reference(id, "method_definition|bar")
    assert_nil(err, "add_reference should not error")
    assert_equal(2, #added.location.reference, "should have 2 references")
    assert_equal("function_declaration|foo", added.location.reference[1])
    assert_equal("method_definition|bar", added.location.reference[2])

    -- Add duplicate reference (no-op)
    local dup, dup_err = issue.add_reference(id, "function_declaration|foo")
    assert_nil(dup_err, "adding duplicate should not error")
    assert_equal(2, #dup.location.reference, "duplicate add should not increase count")

    -- Remove reference
    local removed, rem_err = issue.remove_reference(id, "function_declaration|foo")
    assert_nil(rem_err, "remove_reference should not error")
    assert_equal(1, #removed.location.reference, "should have 1 reference after removal")
    assert_equal("method_definition|bar", removed.location.reference[1])

    -- Remove non-existent reference
    local _, bad_err = issue.remove_reference(id, "nonexistent|ref")
    assert_not_nil(bad_err, "removing non-existent reference should error")

    -- Verify persisted
    issue._reset()
    local reread = issue.read(id)
    assert_equal(1, #reread.location.reference, "reference change should persist")
    assert_equal("method_definition|bar", reread.location.reference[1])

    teardown(dir)
end

local function test_multiline_block_content()
    local dir = setup_project("")

    local original = {
        id = "20260110_143256",
        version = 1,
        status = "OPEN",
        location = { filepath = "src/main.lua", reference = {} },
        blocks = {
            ["Issue Description"] = "Line one.\n\nLine three.\n\n### Sub-heading\nMore content.",
        },
        mtime = 0,
    }

    local content = issue.serialize(original)
    local deserialized = issue.deserialize(content)

    assert_equal(original.blocks["Issue Description"],
        deserialized.blocks["Issue Description"],
        "multiline block content should round-trip")

    teardown(dir)
end

local function test_write_and_mtime()
    local dir = setup_project("")

    local loc = { filepath = "src/main.lua", reference = {} }

    local created, _ = issue.create(loc, "Original.")
    assert_true(created.mtime > 0, "mtime should be set after create")

    -- Modify and write
    created.blocks["Issue Description"] = "Modified."
    local ok, err = issue.write(created)
    assert_true(ok, "write should succeed")
    assert_nil(err, "write should not error")

    -- Read back and verify
    issue._reset()
    local reread = issue.read(created.id)
    assert_equal("Modified.", reread.blocks["Issue Description"],
        "modified content should persist")

    teardown(dir)
end

local function test_file_scoped_location()
    local dir = setup_project("")

    -- File-scoped location (no references)
    local loc = { filepath = "src/main.lua", reference = {} }
    local original = {
        id = "20260110_143256",
        version = 1,
        status = "OPEN",
        location = loc,
        blocks = {},
        mtime = 0,
    }

    local content = issue.serialize(original)
    local deserialized = issue.deserialize(content)

    assert_not_nil(deserialized.location, "file-scoped location should be present")
    assert_equal("src/main.lua", deserialized.location.filepath)
    assert_equal(0, #deserialized.location.reference, "should have no references")

    teardown(dir)
end

local function test_resolve()
    local dir = setup_project("")

    local loc = { filepath = "src/main.lua", reference = {} }
    local created, _ = issue.create(loc, "A bug.")
    local id = created.id

    -- Resolve
    local resolved, err = issue.resolve(id, "Fixed the null pointer.")
    assert_nil(err, "resolve should not error")
    assert_equal("CLOSED", resolved.status, "resolved issue should be CLOSED")
    assert_not_nil(resolved.blocks["Issue Resolution"], "should have Issue Resolution block")

    -- Verify resolution content has UTC timestamp + description
    local resolution = resolved.blocks["Issue Resolution"]
    assert_match("UTC", resolution, "resolution should contain UTC timestamp")
    assert_match("Fixed the null pointer%.", resolution, "resolution should contain description")

    -- Verify persisted to disk
    issue._reset()
    local reread = issue.read(id)
    assert_equal("CLOSED", reread.status, "resolved status should persist")
    assert_not_nil(reread.blocks["Issue Resolution"], "resolution block should persist")
    assert_match("Fixed the null pointer%.", reread.blocks["Issue Resolution"],
        "resolution description should persist")

    -- Verify index updated
    issue_index.flush()
    issue_index._clear()
    local entry = issue_index.get("src/main.lua")
    assert_equal("closed", entry.issues[id], "index should reflect closed status after resolve")

    teardown(dir)
end

local function test_resolve_only_open()
    local dir = setup_project("")

    local loc = { filepath = "src/main.lua", reference = {} }
    local created, _ = issue.create(loc, "A bug.")
    local id = created.id

    -- Close the issue first via resolve
    issue.resolve(id, "Initial resolution.")

    -- Try to resolve a closed issue
    local result, err = issue.resolve(id, "Attempting to resolve closed issue.")
    assert_nil(result, "resolve on CLOSED issue should return nil")
    assert_not_nil(err, "resolve on CLOSED issue should return error")
    assert_match("CLOSED", err, "error should mention current status")

    teardown(dir)
end

local function test_reopen_renames_resolution()
    local dir = setup_project("")

    local loc = { filepath = "src/main.lua", reference = {} }
    local created, _ = issue.create(loc, "A bug.")
    local id = created.id

    -- First resolve/reopen cycle
    issue.resolve(id, "First fix attempt.")
    local reopened1, err1 = issue.reopen(id)
    assert_nil(err1, "first reopen should not error")
    assert_equal("OPEN", reopened1.status, "reopened issue should be OPEN")
    assert_nil(reopened1.blocks["Issue Resolution"], "Issue Resolution should be renamed")
    assert_not_nil(reopened1.blocks["Resolution Attempt 0"],
        "should have Resolution Attempt 0")
    assert_match("First fix attempt%.", reopened1.blocks["Resolution Attempt 0"],
        "Resolution Attempt 0 should contain first description")

    -- Second resolve/reopen cycle
    issue.resolve(id, "Second fix attempt.")
    local reopened2, err2 = issue.reopen(id)
    assert_nil(err2, "second reopen should not error")
    assert_equal("OPEN", reopened2.status, "reopened issue should be OPEN")
    assert_nil(reopened2.blocks["Issue Resolution"], "Issue Resolution should be renamed again")
    assert_not_nil(reopened2.blocks["Resolution Attempt 0"],
        "Resolution Attempt 0 should still exist")
    assert_not_nil(reopened2.blocks["Resolution Attempt 1"],
        "should have Resolution Attempt 1")
    assert_match("First fix attempt%.", reopened2.blocks["Resolution Attempt 0"],
        "Resolution Attempt 0 should still contain first description")
    assert_match("Second fix attempt%.", reopened2.blocks["Resolution Attempt 1"],
        "Resolution Attempt 1 should contain second description")

    -- Verify persisted to disk
    issue._reset()
    local reread = issue.read(id)
    assert_equal("OPEN", reread.status, "reopened status should persist")
    assert_not_nil(reread.blocks["Resolution Attempt 0"], "Attempt 0 should persist")
    assert_not_nil(reread.blocks["Resolution Attempt 1"], "Attempt 1 should persist")
    assert_nil(reread.blocks["Issue Resolution"], "no Issue Resolution after reopen")

    teardown(dir)
end

local function test_reopen_only_closed()
    local dir = setup_project("")

    local loc = { filepath = "src/main.lua", reference = {} }
    local created, _ = issue.create(loc, "A bug.")
    local id = created.id

    -- Try to reopen an OPEN issue
    local result, err = issue.reopen(id)
    assert_nil(result, "reopen on OPEN issue should return nil")
    assert_not_nil(err, "reopen on OPEN issue should return error")
    assert_match("OPEN", err, "error should mention current status")

    teardown(dir)
end

local function test_create_collision_backtrack()
    local dir = setup_project("")

    local loc = { filepath = "src/main.lua", reference = { "function_declaration|my_func" } }

    -- Create a first issue (takes the current-second ID)
    local first, err1 = issue.create(loc, "First issue.")
    assert_nil(err1, "first create should not error")
    assert_not_nil(first, "first create should return issue")
    local first_id = first.id

    -- Pre-create a directory for the current-second ID to simulate another collision
    local current_id = require("huginn.modules.time").generate_id_with_offset(0)
    if current_id ~= first_id then
        local current_path = issue.issue_path(current_id)
        vim.fn.mkdir(filepath.dirname(current_path), "p")
    end

    -- Create a second issue — should backtrack to find an unused ID
    local second, err2 = issue.create(loc, "Second issue.")
    assert_nil(err2, "second create should not error")
    assert_not_nil(second, "second create should return issue")
    assert_true(second.id ~= first_id, "second issue should have a different ID than first")

    -- Both issues should exist on disk
    local first_path = issue.issue_path(first_id)
    assert_true(filepath.exists(first_path), "first Issue.md should exist on disk")
    local second_path = issue.issue_path(second.id)
    assert_true(filepath.exists(second_path), "second Issue.md should exist on disk")

    -- The second ID should be an earlier timestamp (backtracked)
    assert_true(second.id < first_id, "backtracked ID should be earlier than first ID")

    teardown(dir)
end

function M.run()
    local runner = TestRunner.new("issue")

    runner:test("issue_path: correct materialization from ID", test_issue_path)
    runner:test("serialize/deserialize: basic round-trip", test_serialize_deserialize_basic)
    runner:test("serialize: no location", test_serialize_no_location)
    runner:test("serialize: custom blocks and ordering", test_serialize_custom_blocks)
    runner:test("serialize: multiple references", test_serialize_multiple_references)
    runner:test("serialize: file-scoped location (no references)", test_file_scoped_location)
    runner:test("serialize: multiline block content round-trip", test_multiline_block_content)
    runner:test("deserialize: error recovery (missing H1, duplicate H2, bad location)", test_deserialize_error_recovery)
    runner:test("create and read: disk persistence and cache", test_create_and_read)
    runner:test("create: empty description", test_create_empty_description)
    runner:test("write and mtime tracking", test_write_and_mtime)
    runner:test("close and reopen: status transitions", test_close_and_reopen)
    runner:test("relocate: filepath migration and reindex", test_relocate)
    runner:test("relocate: closed issue preserves status in index", test_relocate_closed_issue)
    runner:test("add_reference and remove_reference", test_references)
    runner:test("resolve: creates resolution block and closes issue", test_resolve)
    runner:test("resolve: only works on OPEN issues", test_resolve_only_open)
    runner:test("reopen: renames resolution block to attempt N", test_reopen_renames_resolution)
    runner:test("reopen: only works on CLOSED issues", test_reopen_only_closed)
    runner:test("create: collision backtrack finds unused ID", test_create_collision_backtrack)

    runner:run()
end

return M
