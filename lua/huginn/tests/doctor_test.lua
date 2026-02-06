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

-- doctor_test.lua
-- Tests for the doctor module (scan functionality)

local M = {}

local doctor = require("huginn.modules.doctor")
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

--- Create a source file in the project
---@param dir string project root
---@param rel_path string relative path
---@param content string[] file lines
local function create_source_file(dir, rel_path, content)
    local abs_path = filepath.join(dir, rel_path)
    vim.fn.mkdir(filepath.dirname(abs_path), "p")
    vim.fn.writefile(content, abs_path)
end

local function test_scan_without_context()
    context._reset()
    config.active = {}
    config.huginn_path = nil

    local results, err = doctor.scan(nil, nil)
    assert_not_nil(err, "scan should return error without context")
    assert_nil(results, "scan should return nil results without context")
end

local function test_scan_no_issues()
    local dir = setup_project("")
    local ctx = context.get()

    create_source_file(dir, "src/main.lua", { "local x = 1" })

    local results, err = doctor.scan(ctx.cwd, ctx.config)
    assert_nil(err, "scan should not error")
    assert_not_nil(results, "scan should return results")
    assert_equal(0, results.total, "total should be 0")
    assert_equal(0, #results.ok, "ok should be empty")
    assert_equal(0, #results.missing_file, "missing_file should be empty")
    assert_equal(0, #results.broken_refs, "broken_refs should be empty")
    assert_equal(0, #results.missing_index, "missing_index should be empty")

    teardown(dir)
end

local function test_scan_all_healthy()
    local dir = setup_project("")
    local ctx = context.get()

    create_source_file(dir, "src/main.lua", { "local x = 1" })

    local loc = { filepath = "src/main.lua", reference = {} }
    local created, create_err = issue.create(loc, "A healthy issue")
    assert_nil(create_err, "issue creation should not error")
    assert_not_nil(created, "issue should be created")

    local results, err = doctor.scan(ctx.cwd, ctx.config)
    assert_nil(err, "scan should not error")
    assert_equal(1, results.total, "total should be 1")
    assert_equal(1, #results.ok, "ok should have 1 entry")
    assert_equal(0, #results.missing_file, "missing_file should be empty")
    assert_equal(0, #results.broken_refs, "broken_refs should be empty")
    assert_equal(0, #results.missing_index, "missing_index should be empty")

    teardown(dir)
end

local function test_scan_missing_file()
    local dir = setup_project("")
    local ctx = context.get()

    -- Create a source file, create an issue, then delete the file
    create_source_file(dir, "src/gone.lua", { "local x = 1" })

    local loc = { filepath = "src/gone.lua", reference = {} }
    local created, create_err = issue.create(loc, "Issue for a file that will vanish")
    assert_nil(create_err, "issue creation should not error")
    assert_not_nil(created, "issue should be created")

    -- Delete the source file
    vim.fn.delete(filepath.join(dir, "src/gone.lua"))

    local results, err = doctor.scan(ctx.cwd, ctx.config)
    assert_nil(err, "scan should not error")
    assert_equal(1, results.total, "total should be 1")
    assert_equal(0, #results.ok, "ok should be empty")
    assert_equal(1, #results.missing_file, "missing_file should have 1 entry")
    assert_equal(created.id, results.missing_file[1].issue_id, "missing_file should have correct issue ID")
    assert_equal("src/gone.lua", results.missing_file[1].rel_filepath, "should have correct filepath")

    teardown(dir)
end

local function test_scan_broken_refs()
    local dir = setup_project("")
    local ctx = context.get()

    -- Create a Lua source file with a function
    create_source_file(dir, "src/main.lua", {
        "local function hello()",
        "    return 1",
        "end",
        "return { hello = hello }",
    })

    -- Create an issue referencing a function that does NOT exist
    local loc = { filepath = "src/main.lua", reference = { "function_declaration|nonexistent_func" } }
    local created, create_err = issue.create(loc, "Issue with broken ref")
    assert_nil(create_err, "issue creation should not error")
    assert_not_nil(created, "issue should be created")

    local results, err = doctor.scan(ctx.cwd, ctx.config)
    assert_nil(err, "scan should not error")
    assert_equal(1, results.total, "total should be 1")
    assert_equal(1, #results.broken_refs, "broken_refs should have 1 entry")
    assert_equal(created.id, results.broken_refs[1].issue_id, "broken_refs should have correct issue ID")
    assert_not_nil(results.broken_refs[1].broken_refs, "should have broken_refs list")
    assert_equal(1, #results.broken_refs[1].broken_refs, "should have 1 broken ref")
    assert_equal("function_declaration|nonexistent_func", results.broken_refs[1].broken_refs[1],
        "should identify the broken ref")

    teardown(dir)
end

local function test_scan_mixed_states()
    local dir = setup_project("")
    local ctx = context.get()

    -- File 1: healthy issue (no refs)
    create_source_file(dir, "src/healthy.lua", { "local x = 1" })
    local _, err1 = issue.create({ filepath = "src/healthy.lua", reference = {} }, "Healthy")
    assert_nil(err1)

    -- File 2: missing file
    create_source_file(dir, "src/gone.lua", { "local y = 2" })
    local _, err2 = issue.create({ filepath = "src/gone.lua", reference = {} }, "Will vanish")
    assert_nil(err2)
    vim.fn.delete(filepath.join(dir, "src/gone.lua"))

    local results, err = doctor.scan(ctx.cwd, ctx.config)
    assert_nil(err, "scan should not error")
    assert_equal(2, results.total, "total should be 2")
    assert_equal(1, #results.ok, "ok should have 1 entry")
    assert_equal(1, #results.missing_file, "missing_file should have 1 entry")

    teardown(dir)
end

local function test_auto_repair_missing_index()
    local dir = setup_project("")
    local ctx = context.get()

    -- Create a source file and issue
    create_source_file(dir, "src/main.lua", { "local x = 1" })
    local loc = { filepath = "src/main.lua", reference = {} }
    local created, create_err = issue.create(loc, "Test issue")
    assert_nil(create_err)
    assert_not_nil(created)

    -- Manually modify the issue's location to a different filepath
    -- without updating the index, simulating a missing cross-index
    local iss = created
    iss.location.filepath = "src/other.lua"
    issue.write(iss)

    -- Create the "other" source file so it doesn't trip the missing_file check
    create_source_file(dir, "src/other.lua", { "local y = 2" })

    -- Scan: the issue is indexed under src/main.lua but location says src/other.lua
    -- The index for src/other.lua doesn't have this issue
    local results, err = doctor.scan(ctx.cwd, ctx.config)
    assert_nil(err, "scan should not error")
    assert_equal(1, #results.missing_index, "should detect missing index entry")

    -- Run auto-repair
    local count = 0
    for _, item in ipairs(results.missing_index) do
        if item.issue.location then
            issue_index.create(item.issue.location.filepath, item.issue_id)
            if item.issue.status == "CLOSED" then
                issue_index.close(item.issue.location.filepath, item.issue_id)
            end
            count = count + 1
        end
    end
    issue_index.flush()
    assert_equal(1, count, "should repair 1 entry")

    -- Verify the index entry now exists
    local entry = issue_index.get("src/other.lua")
    assert_not_nil(entry, "index entry should now exist for src/other.lua")
    assert_true(entry:has(iss.id), "index entry should contain the issue ID")

    teardown(dir)
end

function M.run()
    local runner = TestRunner.new("doctor")

    runner:test("scan without context returns error", test_scan_without_context)
    runner:test("scan with no issues returns empty results", test_scan_no_issues)
    runner:test("scan all healthy classifies as ok", test_scan_all_healthy)
    runner:test("scan missing file classifies correctly", test_scan_missing_file)
    runner:test("scan broken refs classifies correctly", test_scan_broken_refs)
    runner:test("scan mixed states classifies correctly", test_scan_mixed_states)
    runner:test("auto-repair missing index creates entry", test_auto_repair_missing_index)

    runner:run()
end

return M
