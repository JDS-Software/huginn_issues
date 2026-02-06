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

-- issue_index_test.lua
-- Tests for the issue index module

local M = {}

local issue_index = require("huginn.modules.issue_index")
local context = require("huginn.modules.context")
local config = require("huginn.modules.config")
local filepath = require("huginn.modules.filepath")
local logging = require("huginn.modules.logging")

local IndexEntry = issue_index._IndexEntry

--- Create a temp project directory with a .huginn file and initialize context
---@param huginn_content string? .huginn file content
---@return string dir absolute path to temp directory
local function setup_project(huginn_content)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local huginn_path = dir .. "/.huginn"
    vim.fn.writefile(vim.split(huginn_content or "", "\n"), huginn_path)

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
    issue_index._clear()
    context._reset()
    config.active = {}
    config.huginn_path = nil
    vim.fn.delete(dir, "rf")
end

--- Reset module state without filesystem cleanup
local function reset()
    issue_index._clear()
    context._reset()
    config.active = {}
    config.huginn_path = nil
end

local function test_index_entry()
    -- new creates clean entry
    local entry = IndexEntry.new("src/main.lua")
    assert_equal("src/main.lua", entry.filepath, "filepath should be set")
    assert_false(entry.dirty, "new entry should not be dirty")
    assert_true(entry:is_empty(), "new entry should be empty")

    -- set marks dirty
    entry:set("20260110_111401", "open")
    assert_true(entry.dirty, "set should mark dirty")
    assert_true(entry:has("20260110_111401"), "has should return true after set")
    assert_equal("open", entry.issues["20260110_111401"], "status should be open")
    assert_false(entry:is_empty(), "entry should not be empty after set")

    -- set can update status
    entry.dirty = false
    entry:set("20260110_111401", "closed")
    assert_true(entry.dirty, "updating status should mark dirty")
    assert_equal("closed", entry.issues["20260110_111401"], "status should be updated")

    -- remove marks dirty
    entry.dirty = false
    entry:set("20260110_111402", "open")
    entry.dirty = false
    entry:remove("20260110_111402")
    assert_true(entry.dirty, "remove should mark dirty")
    assert_false(entry:has("20260110_111402"), "has should be false after remove")

    -- remove of non-existent issue does not mark dirty
    entry.dirty = false
    entry:remove("nonexistent")
    assert_false(entry.dirty, "removing non-existent should not mark dirty")

    -- is_empty after removing all
    entry:remove("20260110_111401")
    assert_true(entry:is_empty(), "should be empty after removing all issues")
end

local function test_parse_and_serialize()
    -- basic parse
    local content = "[src/main.lua]\n20260110_111401 = open\n20260110_111402 = closed\n"
    local entries = issue_index.parse_index_file(content)
    assert_not_nil(entries["src/main.lua"], "should parse section")
    local entry = entries["src/main.lua"]
    assert_equal("open", entry.issues["20260110_111401"], "should parse open status")
    assert_equal("closed", entry.issues["20260110_111402"], "should parse closed status")
    assert_false(entry.dirty, "parsed entries should not be dirty")

    -- multi-section (collision) parse
    local multi = "[src/a.lua]\n20260110_111401 = open\n\n[src/b.lua]\n20260110_111402 = closed\n"
    local multi_entries = issue_index.parse_index_file(multi)
    assert_not_nil(multi_entries["src/a.lua"], "should parse first section")
    assert_not_nil(multi_entries["src/b.lua"], "should parse second section")

    -- malformed values skipped
    local bad = "[src/main.lua]\n20260110_111401 = bogus\n20260110_111402 = open\n"
    local bad_entries = issue_index.parse_index_file(bad)
    local bad_entry = bad_entries["src/main.lua"]
    assert_false(bad_entry:has("20260110_111401"), "malformed status should be skipped")
    assert_true(bad_entry:has("20260110_111402"), "valid status should be kept")

    -- round-trip: serialize then parse produces equivalent data
    local original = {
        ["src/main.lua"] = IndexEntry.new("src/main.lua"),
        ["src/other.lua"] = IndexEntry.new("src/other.lua"),
    }
    original["src/main.lua"]:set("20260110_111401", "open")
    original["src/other.lua"]:set("20260110_111402", "closed")
    local serialized = issue_index.serialize_entries(original)
    local roundtrip = issue_index.parse_index_file(serialized)
    assert_equal("open", roundtrip["src/main.lua"].issues["20260110_111401"], "round-trip open")
    assert_equal("closed", roundtrip["src/other.lua"].issues["20260110_111402"], "round-trip closed")

    -- empty entries are excluded from serialization
    local with_empty = {
        ["src/empty.lua"] = IndexEntry.new("src/empty.lua"),
        ["src/has.lua"] = IndexEntry.new("src/has.lua"),
    }
    with_empty["src/has.lua"]:set("20260110_111401", "open")
    local ser = issue_index.serialize_entries(with_empty)
    local parsed_back = issue_index.parse_index_file(ser)
    assert_nil(parsed_back["src/empty.lua"], "empty entry should not be serialized")
    assert_not_nil(parsed_back["src/has.lua"], "non-empty entry should be serialized")
end

local function test_hash_utilities()
    -- compute_hash returns consistent truncated result
    local hash16 = issue_index._compute_hash("src/main.lua", 16)
    assert_equal(16, #hash16, "hash should be 16 chars at key_length=16")

    local hash32 = issue_index._compute_hash("src/main.lua", 32)
    assert_equal(32, #hash32, "hash should be 32 chars at key_length=32")

    -- longer hash is a prefix extension of shorter
    assert_equal(hash16, string.sub(hash32, 1, 16), "hash32 should extend hash16")

    -- full 64-char hash
    local hash64 = issue_index._compute_hash("src/main.lua", 64)
    assert_equal(64, #hash64, "hash should be 64 chars at key_length=64")

    -- clamp_key_length boundaries
    assert_equal(16, issue_index._clamp_key_length(1), "below min should clamp to 16")
    assert_equal(16, issue_index._clamp_key_length(15), "just below min should clamp to 16")
    assert_equal(16, issue_index._clamp_key_length(16), "at min should stay 16")
    assert_equal(32, issue_index._clamp_key_length(32), "mid-range should stay")
    assert_equal(64, issue_index._clamp_key_length(64), "at max should stay 64")
    assert_equal(64, issue_index._clamp_key_length(100), "above max should clamp to 64")
    assert_equal(20, issue_index._clamp_key_length(20.7), "float should floor")

    -- hash_to_path uses 3-char fanout prefix
    local path = issue_index._hash_to_path("/project/issues", "abc123456789abcd")
    assert_match("%.index/abc/abc123456789abcd$", path, "path should use fanout scheme")
end

local function test_get_and_create()
    -- get returns nil before context init
    reset()
    local entry, err = issue_index.get("some/file.lua")
    assert_nil(entry, "get should return nil without context")
    assert_not_nil(err, "get should return error without context")

    -- get returns nil for unknown filepath
    local dir = setup_project("")
    local source = "src/main.lua"
    entry, err = issue_index.get(source)
    assert_nil(entry, "get should return nil for unknown filepath")
    assert_nil(err, "get should not error for unknown filepath")

    -- create persists to disk and returns entry
    local created, create_err = issue_index.create(source, "20260110_111401")
    assert_not_nil(created, "create should return entry")
    assert_nil(create_err, "create should not error")
    assert_equal("open", created.issues["20260110_111401"], "created issue should be open")
    assert_false(created.dirty, "write-through should clear dirty flag")

    -- verify file exists on disk
    local ctx = context.get()
    local issue_dir = filepath.join(ctx.cwd, ctx.config.plugin.issue_dir)
    local hash = vim.fn.sha256(source)
    local truncated = string.sub(hash, 1, ctx.config.index.key_length)
    local index_path = filepath.join(issue_dir, ".index", string.sub(truncated, 1, 3), truncated)
    assert_true(filepath.exists(index_path), "index file should exist on disk after create")

    -- .gitignore created alongside index
    local gitignore_path = filepath.join(issue_dir, ".index", ".gitignore")
    assert_true(filepath.exists(gitignore_path), ".gitignore should exist in .index/")
    local gitignore_content = table.concat(vim.fn.readfile(gitignore_path), "\n")
    assert_equal("*", gitignore_content, ".gitignore should contain only *")

    -- get returns cached entry after create
    local fetched = issue_index.get(source)
    assert_not_nil(fetched, "get should return entry after create")
    assert_equal("open", fetched.issues["20260110_111401"], "fetched issue should be open")

    -- get loads from disk on cache miss
    issue_index._clear()
    local reloaded = issue_index.get(source)
    assert_not_nil(reloaded, "get should load from disk on cache miss")
    assert_equal("open", reloaded.issues["20260110_111401"], "disk-loaded issue should be open")

    -- create second issue for same file
    issue_index.create(source, "20260110_111402")
    local multi = issue_index.get(source)
    assert_true(multi:has("20260110_111401"), "first issue should still exist")
    assert_true(multi:has("20260110_111402"), "second issue should exist")

    teardown(dir)
end

local function test_status_mutations()
    local dir = setup_project("")
    local source = "src/main.lua"
    issue_index.create(source, "20260110_111401")

    -- close
    local ok, err = issue_index.close(source, "20260110_111401")
    assert_true(ok, "close should succeed")
    assert_nil(err, "close should not error")
    local entry = issue_index.get(source)
    assert_equal("closed", entry.issues["20260110_111401"], "close should set status to closed")
    assert_true(entry.dirty, "close should mark dirty")

    -- reopen
    ok, err = issue_index.reopen(source, "20260110_111401")
    assert_true(ok, "reopen should succeed")
    assert_nil(err, "reopen should not error")
    entry = issue_index.get(source)
    assert_equal("open", entry.issues["20260110_111401"], "reopen should set status to open")

    -- remove
    issue_index.create(source, "20260110_111402")
    ok, err = issue_index.remove(source, "20260110_111402")
    assert_true(ok, "remove should succeed")
    assert_nil(err, "remove should not error")
    entry = issue_index.get(source)
    assert_false(entry:has("20260110_111402"), "removed issue should not exist")
    assert_true(entry:has("20260110_111401"), "other issue should still exist")

    -- error cases
    ok, err = issue_index.close(source, "nonexistent")
    assert_false(ok, "close nonexistent should fail")
    assert_not_nil(err, "close nonexistent should return error")

    ok, err = issue_index.close("no/such/file.lua", "20260110_111401")
    assert_false(ok, "close unknown file should fail")

    teardown(dir)
end

local function test_flush()
    local dir = setup_project("")
    local source = "src/main.lua"
    issue_index.create(source, "20260110_111401")

    -- close marks dirty but doesn't persist
    issue_index.close(source, "20260110_111401")
    local entry = issue_index.get(source)
    assert_true(entry.dirty, "should be dirty before flush")

    -- flush persists and clears dirty
    issue_index.flush()
    entry = issue_index.get(source)
    assert_false(entry.dirty, "should not be dirty after flush")

    -- verify persisted to disk
    issue_index._clear()
    entry = issue_index.get(source)
    assert_not_nil(entry, "should reload from disk after flush")
    assert_equal("closed", entry.issues["20260110_111401"], "flushed status should be persisted")

    -- flush is no-op when clean
    issue_index.flush() -- should not error

    teardown(dir)
end

local function test_full_scan()
    local dir = setup_project("")
    local source_a = "src/a.lua"
    local source_b = "src/b.lua"

    -- create some entries
    issue_index.create(source_a, "20260110_111401")
    issue_index.create(source_b, "20260110_111402")

    -- full_scan clears cache and reloads
    issue_index._clear()
    local count, err = issue_index.full_scan()
    assert_nil(err, "full_scan should not error")
    assert_equal(2, count, "full_scan should find 2 entries")

    -- verify entries are accessible after scan
    local entry_a = issue_index.get(source_a)
    assert_not_nil(entry_a, "should find entry for a.lua after scan")
    assert_equal("open", entry_a.issues["20260110_111401"], "a.lua issue should be open")

    local entry_b = issue_index.get(source_b)
    assert_not_nil(entry_b, "should find entry for b.lua after scan")

    -- full_scan with no .index/ directory returns 0
    issue_index._clear()
    local empty_dir = setup_project("")
    count, err = issue_index.full_scan()
    assert_nil(err, "full_scan should not error with no .index dir")
    assert_equal(0, count, "full_scan should return 0 with no .index dir")

    teardown(empty_dir)
    teardown(dir)
end

local function test_all_entries()
    local dir = setup_project("")
    local source_a = "src/a.lua"
    local source_b = "src/b.lua"

    -- empty cache returns empty table
    local empty = issue_index.all_entries()
    assert_not_nil(empty, "all_entries should return a table")
    assert_nil(next(empty), "all_entries should be empty with no data")

    -- create entries and full_scan
    issue_index.create(source_a, "20260110_111401")
    issue_index.create(source_b, "20260110_111402")
    issue_index._clear()
    issue_index.full_scan()

    local entries = issue_index.all_entries()
    assert_not_nil(entries[source_a], "all_entries should contain a.lua")
    assert_not_nil(entries[source_b], "all_entries should contain b.lua")
    assert_equal("open", entries[source_a].issues["20260110_111401"], "a.lua issue should be open")
    assert_equal("open", entries[source_b].issues["20260110_111402"], "b.lua issue should be open")

    -- returns a new table each call
    local entries2 = issue_index.all_entries()
    assert_true(entries ~= entries2, "all_entries should return a new table each call")

    teardown(dir)
end

local function test_setup()
    local dir = setup_project("")

    issue_index.setup()

    local autocmds = vim.api.nvim_get_autocmds({ group = "HuginnIndex" })
    assert_true(#autocmds >= 2, "setup should create at least 2 autocmds")

    -- clean up augroup
    vim.api.nvim_create_augroup("HuginnIndex", { clear = true })
    teardown(dir)
end

local function test_migration()
    -- create entries with key_length=16
    local dir = setup_project("[index]\nkey_length = 16")
    local source = "src/main.lua"
    issue_index.create(source, "20260110_111401")

    -- verify initial index file name length
    local ctx = context.get()
    local issue_dir = filepath.join(ctx.cwd, ctx.config.plugin.issue_dir)
    local hash16 = string.sub(vim.fn.sha256(source), 1, 16)
    local old_path = filepath.join(issue_dir, ".index", string.sub(hash16, 1, 3), hash16)
    assert_true(filepath.exists(old_path), "16-char index file should exist")

    -- migrate to key_length=32 (update config first, as the real listener would)
    ctx.config.index.key_length = 32
    issue_index.migrate_key_length(32)

    -- old file should be gone, new file should exist
    assert_false(filepath.exists(old_path), "old 16-char file should be deleted after migration")
    local hash32 = string.sub(vim.fn.sha256(source), 1, 32)
    local new_path = filepath.join(issue_dir, ".index", string.sub(hash32, 1, 3), hash32)
    assert_true(filepath.exists(new_path), "32-char index file should exist after migration")

    -- data should be preserved
    local entry = issue_index.get(source)
    assert_not_nil(entry, "entry should be accessible after migration")
    assert_equal("open", entry.issues["20260110_111401"], "issue data should be preserved")

    teardown(dir)
end

local function test_check_integrity()
    local dir = setup_project("")
    local source_a = "src/a.lua"
    local source_b = "src/b.lua"

    issue_index.create(source_a, "20260110_111401")
    issue_index.create(source_a, "20260110_111402")
    issue_index.create(source_b, "20260110_111403")

    local ctx = context.get()
    local issue_dir = filepath.join(ctx.cwd, ctx.config.plugin.issue_dir)

    -- all issues exist: nothing evicted
    local results = issue_index.check_integrity(issue_dir, function() return true end)
    assert_equal(3, results.checked, "should check all 3 entries")
    assert_equal(0, results.evicted, "should evict nothing when all exist")

    -- one issue missing: evicted from disk and reported
    issue_index.create(source_a, "20260110_111401")
    issue_index.create(source_a, "20260110_111402")
    issue_index.create(source_b, "20260110_111403")
    results = issue_index.check_integrity(issue_dir, function(_, id)
        return id ~= "20260110_111402"
    end)
    assert_equal(3, results.checked, "should check all 3 entries")
    assert_equal(1, results.evicted, "should evict the missing one")
    assert_equal("20260110_111402", results.evicted_ids[1], "should report evicted ID")

    -- verify disk was updated
    local entry = issue_index.get(source_a)
    assert_not_nil(entry, "entry should still exist for source_a")
    assert_true(entry:has("20260110_111401"), "surviving issue should remain")
    assert_false(entry:has("20260110_111402"), "evicted issue should be gone")

    -- all issues missing: index file deleted, entries gone
    issue_index.create(source_a, "20260110_111404")
    issue_index.create(source_a, "20260110_111405")
    results = issue_index.check_integrity(issue_dir, function() return false end)
    assert_true(results.evicted > 0, "should evict all entries")
    entry = issue_index.get(source_a)
    assert_nil(entry, "all entries should be gone after full eviction")

    -- no index directory: returns zeros
    issue_index._clear()
    local empty_dir = setup_project("")
    local empty_issue_dir = filepath.join(vim.fn.tempname(), "issues")
    results = issue_index.check_integrity(empty_issue_dir, function() return true end)
    assert_equal(0, results.checked, "should check 0 with no index dir")
    assert_equal(0, results.evicted, "should evict 0 with no index dir")

    teardown(empty_dir)
    teardown(dir)
end

function M.run()
    local runner = TestRunner.new("issue_index")

    runner:test("IndexEntry class: new, set, remove, has, is_empty", test_index_entry)
    runner:test("parse and serialize: basic, multi-section, round-trip, malformed", test_parse_and_serialize)
    runner:test("hash utilities: truncation, clamping, path construction", test_hash_utilities)
    runner:test("get and create: cache miss, hit, disk persistence", test_get_and_create)
    runner:test("close, reopen, remove: status mutations and error cases", test_status_mutations)
    runner:test("flush: persists dirty entries and clears flags", test_flush)
    runner:test("full_scan: clears cache and reloads from disk", test_full_scan)
    runner:test("all_entries: returns flat map from cache", test_all_entries)
    runner:test("setup: creates augroup with autocmds", test_setup)
    runner:test("migration: rename files when key_length changes", test_migration)
    runner:test("check_integrity: evicts stale entries, preserves valid ones", test_check_integrity)

    runner:run()
end

return M
