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

-- ini_parser_test.lua
-- Tests for the ini_parser module

local M = {}

local ini_parser = require("huginn.modules.ini_parser")

local function test_parse_basic_structure()
    -- empty input
    local empty = ini_parser.parse("")
    assert_not_nil(empty)
    assert_equal(0, vim.tbl_count(empty))

    -- section header creates table
    local sec = ini_parser.parse("[section]")
    assert_not_nil(sec.section)
    assert_equal("table", type(sec.section))

    -- simple key=value
    local kv = ini_parser.parse("[section]\nkey = value")
    assert_equal("value", kv.section.key)

    -- multiple sections
    local multi = ini_parser.parse("[one]\na = 1\n[two]\nb = 2")
    assert_equal(1, multi.one.a)
    assert_equal(2, multi.two.b)

    -- same section twice merges
    local merged = ini_parser.parse("[section]\na = 1\n[other]\nb = 2\n[section]\nc = 3")
    assert_equal(1, merged.section.a)
    assert_equal(3, merged.section.c)

    -- key without section ignored
    local orphan = ini_parser.parse("key = value\n[section]\nother = test")
    assert_equal("test", orphan.section.other)
    assert_nil(orphan.key)

    -- CRLF line endings
    local crlf = ini_parser.parse("[section]\r\nkey = value\r\n")
    assert_equal("value", crlf.section.key)
end

local function test_parse_value_extraction()
    -- comments ignored
    local commented = ini_parser.parse("[section]\n# this is a comment\nkey = value")
    assert_equal("value", commented.section.key)
    assert_nil(commented.section["#"])

    -- indented comments ignored
    local indented = ini_parser.parse("[section]\n   # indented comment\nkey = value")
    assert_equal("value", indented.section.key)

    -- key whitespace trimmed
    local key_ws = ini_parser.parse("[section]\n   key   = value")
    assert_equal("value", key_ws.section.key)

    -- unquoted value whitespace trimmed
    local val_ws = ini_parser.parse("[section]\nkey =    value   \n")
    assert_equal("value", val_ws.section.key)

    -- unquoted takes first word only
    local first_word = ini_parser.parse("[section]\nkey = value extra stuff")
    assert_equal("value", first_word.section.key)

    -- unquoted ignores inline comments
    local inline = ini_parser.parse("[section]\nkey = value #comment")
    assert_equal("value", inline.section.key)

    -- quoted preserves spaces
    local quoted_sp = ini_parser.parse('[section]\nkey = "value with spaces"')
    assert_equal("value with spaces", quoted_sp.section.key)

    -- quoted preserves leading space
    local lead = ini_parser.parse('[section]\nkey = " value"')
    assert_equal(" value", lead.section.key)

    -- quoted preserves trailing space
    local trail = ini_parser.parse('[section]\nkey = "value "')
    assert_equal("value ", trail.section.key)

    -- quoted ignores text after closing quote
    local after = ini_parser.parse('[section]\nkey = "value" ignored text')
    assert_equal("value", after.section.key)

    -- empty value ignored
    local empty_val = ini_parser.parse("[section]\nkey = ")
    assert_nil(empty_val.section.key)
end

local function test_parse_type_coercion()
    -- integer
    local int = ini_parser.parse("[section]\nkey = 42")
    assert_equal(42, int.section.key)
    assert_equal("number", type(int.section.key))

    -- float
    local float = ini_parser.parse("[section]\nkey = 3.14")
    assert_equal(3.14, float.section.key)
    assert_equal("number", type(float.section.key))

    -- quoted number still coerced
    local qnum = ini_parser.parse('[section]\nkey = "123"')
    assert_equal(123, qnum.section.key)
    assert_equal("number", type(qnum.section.key))

    -- non-numeric stays string
    local str = ini_parser.parse("[section]\nkey = abc123")
    assert_equal("abc123", str.section.key)
    assert_equal("string", type(str.section.key))

    -- boolean true/false (bare and quoted)
    local bt = ini_parser.parse("[section]\nkey = true")
    assert_equal(true, bt.section.key)
    assert_equal("boolean", type(bt.section.key))

    local bf = ini_parser.parse("[section]\nkey = false")
    assert_equal(false, bf.section.key)
    assert_equal("boolean", type(bf.section.key))

    local qt = ini_parser.parse('[section]\nkey = "true"')
    assert_equal(true, qt.section.key)
    assert_equal("boolean", type(qt.section.key))

    local qf = ini_parser.parse('[section]\nkey = "false"')
    assert_equal(false, qf.section.key)
    assert_equal("boolean", type(qf.section.key))
end

local function test_parse_key_behaviors()
    -- duplicate key: last wins
    local dup = ini_parser.parse("[section]\nkey = first\nkey = second")
    assert_equal("second", dup.section.key)

    -- aggregating key creates array
    local agg = ini_parser.parse("[section]\nkey[] = value")
    assert_equal("table", type(agg.section["key[]"]))

    -- aggregating key collects values in order
    local multi = ini_parser.parse("[section]\nkey[] = one\nkey[] = two\nkey[] = three")
    local arr = multi.section["key[]"]
    assert_equal(3, #arr)
    assert_equal("one", arr[1])
    assert_equal("two", arr[2])
    assert_equal("three", arr[3])
end

local function test_parse_file_rejects_invalid_paths()
    local nil_result, nil_err = ini_parser.parse_file(nil)
    assert_nil(nil_result)
    assert_not_nil(nil_err)

    local empty_result, empty_err = ini_parser.parse_file("")
    assert_nil(empty_result)
    assert_not_nil(empty_err)

    local missing_result, missing_err = ini_parser.parse_file("/nonexistent/path/.huginn")
    assert_nil(missing_result)
    assert_match("does not exist", missing_err)
end

-- Serialization: value type coverage
local function test_serialize_value_types()
    -- nil input
    assert_equal("", ini_parser.serialize(nil))
    -- empty table
    assert_equal("", ini_parser.serialize({}))
    -- empty section
    assert_equal("[s]\n", ini_parser.serialize({ s = {} }))
    -- single string key
    assert_equal("[section]\nkey = value\n", ini_parser.serialize({ section = { key = "value" } }))
    -- boolean true
    assert_match("flag = true", ini_parser.serialize({ s = { flag = true } }))
    -- boolean false
    assert_match("flag = false", ini_parser.serialize({ s = { flag = false } }))
    -- integer
    assert_match("count = 42", ini_parser.serialize({ s = { count = 42 } }))
    -- float
    assert_match("ratio = 3.14", ini_parser.serialize({ s = { ratio = 3.14 } }))
    -- string without spaces (unquoted)
    assert_match("name = hello", ini_parser.serialize({ s = { name = "hello" } }))
    -- string with spaces (quoted)
    assert_match('name = "hello world"', ini_parser.serialize({ s = { name = "hello world" } }))
    -- empty string (quoted)
    assert_match('name = ""', ini_parser.serialize({ s = { name = "" } }))
end

-- Serialization: structure (ordering, aggregating keys)
local function test_serialize_structure()
    -- aggregating keys emit one line per element
    local agg = ini_parser.serialize({ s = { ["dir[]"] = { "one", "two", "three" } } })
    assert_match("dir%[%] = one", agg)
    assert_match("dir%[%] = two", agg)
    assert_match("dir%[%] = three", agg)

    -- sections sorted alphabetically by default
    local alpha_first = ini_parser.serialize({ beta = { a = 1 }, alpha = { b = 2 } })
    assert_true(alpha_first:find("%[alpha%]") < alpha_first:find("%[beta%]"),
        "alpha should come before beta")

    -- section_order overrides alphabetical
    local ordered = ini_parser.serialize(
        { alpha = { a = 1 }, beta = { b = 2 } },
        { "beta", "alpha" }
    )
    assert_true(ordered:find("%[beta%]") < ordered:find("%[alpha%]"),
        "beta should come before alpha when ordered")

    -- section_order: unlisted sections appended alphabetically
    local partial = ini_parser.serialize(
        { alpha = { a = 1 }, beta = { b = 2 }, gamma = { c = 3 } },
        { "gamma" }
    )
    assert_true(partial:find("%[gamma%]") < partial:find("%[alpha%]"),
        "gamma (ordered) should come before alpha")
    assert_true(partial:find("%[alpha%]") < partial:find("%[beta%]"),
        "alpha should come before beta (both unordered, alphabetical)")

    -- section_order: nonexistent names silently skipped
    local missing = ini_parser.serialize(
        { alpha = { a = 1 } },
        { "nonexistent", "alpha" }
    )
    assert_match("%[alpha%]", missing)
    assert_nil(missing:find("%[nonexistent%]"))

    -- keys sorted alphabetically within section
    local keys = ini_parser.serialize({ s = { zebra = 1, apple = 2 } })
    assert_true(keys:find("apple") < keys:find("zebra"),
        "apple should come before zebra")
end

-- Serialization: output formatting
local function test_serialize_format()
    -- ends with newline
    local result = ini_parser.serialize({ s = { key = "value" } })
    assert_equal("\n", result:sub(-1))

    -- blank line between sections, not after last
    local multi = ini_parser.serialize({ alpha = { a = 1 }, beta = { b = 2 } })
    assert_match("%[alpha%]\na = 1\n\n%[beta%]", multi)
    assert_not_nil(multi:match("%[beta%]\nb = 2\n$"), "no trailing blank line after last section")
end

-- Serialization: round-trip fidelity
local function test_serialize_roundtrip()
    local function roundtrip(data, label)
        local result = ini_parser.parse(ini_parser.serialize(data))
        assert_true(vim.deep_equal(data, result), "roundtrip failed: " .. label)
    end

    roundtrip({ section = { key = "value" } }, "simple string")
    roundtrip({ section = { on = true, off = false } }, "booleans")
    roundtrip({ section = { count = 42 } }, "integer")
    roundtrip({ section = { ratio = 3.14 } }, "float")
    roundtrip({ section = { path = "some dir/file name" } }, "string with spaces")
    roundtrip({ section = { key = " leading" } }, "string with leading space")
    roundtrip({ section = { key = "trailing " } }, "string with trailing space")
    roundtrip({ section = { ["exclude[]"] = { "one", "two", "three" } } }, "aggregating keys")
    roundtrip({ alpha = { a = "hello" }, beta = { b = 42, c = true } }, "multiple sections")
    roundtrip({ section = {} }, "empty section")
    roundtrip({
        ["src/main.lua"] = {
            ["20260115_120000"] = "open",
            ["20260116_093000"] = "closed",
        },
    }, "index file format")
end

function M.run()
    local runner = TestRunner.new("ini_parser")

    runner:test("parse basic structure", test_parse_basic_structure)
    runner:test("parse value extraction", test_parse_value_extraction)
    runner:test("parse type coercion", test_parse_type_coercion)
    runner:test("parse key behaviors", test_parse_key_behaviors)
    runner:test("parse_file rejects invalid paths", test_parse_file_rejects_invalid_paths)
    runner:test("serialize value types", test_serialize_value_types)
    runner:test("serialize structure", test_serialize_structure)
    runner:test("serialize format", test_serialize_format)
    runner:test("serialize roundtrip", test_serialize_roundtrip)

    runner:run()
end

return M
