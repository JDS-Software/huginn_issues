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

-- location_test.lua
-- Tests for the location module

local M = {}

local location = require("huginn.modules.location")

-- Check if a tree-sitter parser is available for a given language
local function check_parser(filetype, sample)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { sample })
    vim.bo[bufnr].filetype = filetype
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, filetype)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return ok and parser ~= nil
end

local has_ts_parser = check_parser("lua", "local x = 1")
local has_c_parser = check_parser("c", "int main() { return 0; }")
local has_go_parser = check_parser("go", "package main")
local has_js_parser = check_parser("javascript", "function f() {}")

-- Helper: create a buffer with Lua content and parse it
local function make_lua_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].filetype = "lua"
    local parser = vim.treesitter.get_parser(bufnr, "lua")
    parser:parse()
    local root = parser:trees()[1]:root()
    return bufnr, root, parser
end

-- Helper: create a buffer with given content and parse with the specified language
local function make_lang_buffer(lines, filetype)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].filetype = filetype
    local parser = vim.treesitter.get_parser(bufnr, filetype)
    parser:parse()
    local root = parser:trees()[1]:root()
    return bufnr, root, parser
end

-- Helper: collect all scope symbols from a tree
local function collect_scope_symbols(root, source)
    local symbols = {}
    local function walk(node)
        if location._is_named_scope(node) and location._get_symbol(node, source) then
            table.insert(symbols, location._get_symbol(node, source))
        end
        for child in node:iter_children() do
            walk(child)
        end
    end
    walk(root)
    return symbols
end

local function test_ref_helpers()
    -- make_ref
    assert_equal("function_declaration|my_func", location._make_ref("function_declaration", "my_func"))
    assert_equal("method_definition|do_thing", location._make_ref("method_definition", "do_thing"))

    -- parse_ref: valid split
    local t, s = location._parse_ref("function_declaration|my_func")
    assert_equal("function_declaration", t)
    assert_equal("my_func", s)

    -- parse_ref: no pipe returns nil
    local t2, s2 = location._parse_ref("no_pipe_here")
    assert_nil(t2)
    assert_nil(s2)

    -- parse_ref: multiple pipes splits on first only
    local t3, s3 = location._parse_ref("type|sym|extra")
    assert_equal("type", t3)
    assert_equal("sym|extra", s3)

    -- parse_ref: empty type or symbol
    local t4, s4 = location._parse_ref("|symbol")
    assert_equal("", t4)
    assert_equal("symbol", s4)

    local t5, s5 = location._parse_ref("type|")
    assert_equal("type", t5)
    assert_equal("", s5)
end

local function test_serialize_and_deserialize()
    -- File-scoped location round-trips
    local loc = location._make_location("src/main.lua", {})
    local serialized = location.serialize(loc)
    assert_match("%[location%]", serialized)
    assert_match("filepath = src/main.lua", serialized)
    local deserialized, err = location.deserialize(serialized)
    assert_nil(err)
    assert_equal("src/main.lua", deserialized.filepath)
    assert_equal(0, #deserialized.reference)

    -- Single reference round-trips
    local loc2 = location._make_location("src/main.lua", { "function_declaration|my_func" })
    local ser2 = location.serialize(loc2)
    assert_match("reference%[%] = function_declaration|my_func", ser2)
    local de2, err2 = location.deserialize(ser2)
    assert_nil(err2)
    assert_equal(1, #de2.reference)
    assert_equal("function_declaration|my_func", de2.reference[1])

    -- Multiple references round-trip, preserving order
    local refs = { "function_declaration|func_a", "method_definition|do_thing", "class_definition|MyClass" }
    local loc3 = location._make_location("src/main.lua", refs)
    local de3, err3 = location.deserialize(location.serialize(loc3))
    assert_nil(err3)
    assert_equal(3, #de3.reference)
    assert_equal("function_declaration|func_a", de3.reference[1])
    assert_equal("method_definition|do_thing", de3.reference[2])
    assert_equal("class_definition|MyClass", de3.reference[3])

    -- Missing [location] section
    local _, err4 = location.deserialize("[other]\nkey = value\n")
    assert_match("missing %[location%] section", err4)

    -- Missing filepath
    local _, err5 = location.deserialize("[location]\nother = value\n")
    assert_match("missing filepath", err5)

    -- Malformed reference: skipped without logger, warned with logger
    local content = "[location]\nfilepath = src/main.lua\nreference[] = no_pipe\nreference[] = good_type|good_sym\n"
    local de6, err6 = location.deserialize(content)
    assert_nil(err6)
    assert_equal(1, #de6.reference)
    assert_equal("good_type|good_sym", de6.reference[1])

    local logged = {}
    local mock_logger = {
        log = function(_, level, message)
            table.insert(logged, { level = level, message = message })
        end,
    }
    local de7, err7 = location.deserialize(content, mock_logger)
    assert_nil(err7)
    assert_equal(1, #de7.reference)
    assert_equal(1, #logged)
    assert_equal("WARN", logged[1].level)
    assert_match("malformed reference", logged[1].message)
end

local function test_scope_detection_and_innermost_scope()
    if not has_ts_parser then return end

    -- Scope detection: function is a scope, plain variable is not
    local lines = {
        "local function my_func()",
        "  return 1",
        "end",
        "",
        "local x = 42",
    }
    local bufnr, root = make_lua_buffer(lines)

    local found_func = false
    for child in root:iter_children() do
        if child:type():find("function") then
            found_func = true
            assert_true(location._is_named_scope(child), "function node should be a named scope")
            assert_equal("my_func", location._get_symbol(child, bufnr))
        end
        if child:type():find("variable") or child:type():find("assignment") then
            local value_nodes = child:field("value")
            if value_nodes and #value_nodes > 0 and not value_nodes[1]:type():find("function") then
                assert_false(location._is_named_scope(child),
                    "variable assigned to number should not be a named scope")
            end
        end
    end
    assert_true(found_func, "should have found a function node")
    vim.api.nvim_buf_delete(bufnr, { force = true })

    -- Innermost scope: nested functions, outer-only region, file scope
    local lines2 = {
        "local function outer()",
        "  local function inner()",
        "    return 1",
        "  end",
        "  return inner()",
        "end",
        "",
        "local x = 1",
    }
    local bufnr2, root2 = make_lua_buffer(lines2)

    local scope_inner = location._find_innermost_scope(root2, 2, bufnr2)
    assert_not_nil(scope_inner, "should find scope at line 2")
    assert_equal("inner", location._get_symbol(scope_inner, bufnr2))

    local scope_outer = location._find_innermost_scope(root2, 4, bufnr2)
    assert_not_nil(scope_outer, "should find scope at line 4")
    assert_equal("outer", location._get_symbol(scope_outer, bufnr2))

    local scope_none = location._find_innermost_scope(root2, 7, bufnr2)
    assert_nil(scope_none, "should not find scope at line 7")

    vim.api.nvim_buf_delete(bufnr2, { force = true })
end

local function test_from_context_normal_and_visual()
    if not has_ts_parser then return end

    -- No window state returns error
    local _, win_err = location.from_context({ cwd = "/project", buffer = 0, window = nil })
    assert_match("no window state", win_err)

    -- Normal mode: inside function, outside function
    local lines = {
        "local function my_func()",
        "  return 1",
        "end",
        "",
        "local x = 1",
    }
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].filetype = "lua"

    local cmd_ctx = {
        cwd = "/project",
        buffer = bufnr,
        window = {
            filepath = "/project/src/main.lua",
            mode = "n",
            start = { line = 2, col = 1 },
            finish = nil,
        },
    }

    local loc, err = location.from_context(cmd_ctx)
    assert_nil(err)
    assert_equal("src/main.lua", loc.filepath)
    assert_equal(1, #loc.reference)
    assert_match("my_func", loc.reference[1])

    cmd_ctx.window.start = { line = 5, col = 1 }
    local loc2, err2 = location.from_context(cmd_ctx)
    assert_nil(err2)
    assert_equal(0, #loc2.reference, "should be file-scoped when outside any function")

    vim.api.nvim_buf_delete(bufnr, { force = true })

    -- Visual mode: spanning two functions, within one function
    local lines2 = {
        "local function func_a()",
        "  return 1",
        "end",
        "",
        "local function func_b()",
        "  return 2",
        "end",
    }
    local bufnr2 = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr2, 0, -1, false, lines2)
    vim.bo[bufnr2].filetype = "lua"

    local cmd_ctx2 = {
        cwd = "/project",
        buffer = bufnr2,
        window = {
            filepath = "/project/src/main.lua",
            mode = "V",
            start = { line = 2, col = 1 },
            finish = { line = 6, col = 1 },
        },
    }

    local loc3, err3 = location.from_context(cmd_ctx2)
    assert_nil(err3)
    assert_equal(2, #loc3.reference, "should have two references spanning two functions")

    cmd_ctx2.window.start = { line = 1, col = 1 }
    cmd_ctx2.window.finish = { line = 2, col = 1 }
    local loc4, err4 = location.from_context(cmd_ctx2)
    assert_nil(err4)
    assert_equal(1, #loc4.reference, "should have one reference within single function")

    vim.api.nvim_buf_delete(bufnr2, { force = true })
end

local function test_resolve_found_not_found_ambiguous()
    -- File-scoped returns empty table
    local loc0 = location._make_location("src/main.lua", {})
    local res0, err0 = location.resolve("/project", loc0)
    assert_nil(err0)
    assert_equal(0, vim.tbl_count(res0))

    -- File not found returns error
    local loc_nf = location._make_location("nonexistent.lua", { "function_declaration|foo" })
    local res_nf, err_nf = location.resolve("/tmp", loc_nf)
    assert_nil(res_nf)
    assert_match("file not found", err_nf)

    if not has_ts_parser then return end

    -- Found: single matching function
    local lines = { "local function target_func()", "  return 42", "end" }
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].filetype = "lua"
    vim.api.nvim_buf_set_name(bufnr, "/tmp/huginn_test_resolve.lua")

    local parser = vim.treesitter.get_parser(bufnr, "lua")
    parser:parse()
    local root = parser:trees()[1]:root()
    local func_node = location._find_innermost_scope(root, 1, bufnr)
    assert_not_nil(func_node)
    local func_type = func_node:type()

    local loc1 = location._make_location("huginn_test_resolve.lua", { func_type .. "|target_func" })
    local res1, err1 = location.resolve("/tmp", loc1)
    assert_nil(err1)
    local entry1 = res1[func_type .. "|target_func"]
    assert_equal("found", entry1.result)
    assert_not_nil(entry1.node)
    vim.api.nvim_buf_delete(bufnr, { force = true })

    -- Not found: reference to nonexistent symbol
    local lines2 = { "local function existing()", "  return 1", "end" }
    local bufnr2 = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr2, 0, -1, false, lines2)
    vim.bo[bufnr2].filetype = "lua"
    vim.api.nvim_buf_set_name(bufnr2, "/tmp/huginn_test_resolve_nf.lua")

    local loc2 = location._make_location("huginn_test_resolve_nf.lua", { "function_declaration|deleted_func" })
    local res2, err2 = location.resolve("/tmp", loc2)
    assert_nil(err2)
    assert_equal("not_found", res2["function_declaration|deleted_func"].result)
    vim.api.nvim_buf_delete(bufnr2, { force = true })

    -- Ambiguous: two functions with same name
    local lines3 = {
        "local function dupe()", "  return 1", "end",
        "", "local function dupe()", "  return 2", "end",
    }
    local bufnr3 = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr3, 0, -1, false, lines3)
    vim.bo[bufnr3].filetype = "lua"
    vim.api.nvim_buf_set_name(bufnr3, "/tmp/huginn_test_resolve_amb.lua")

    local parser3 = vim.treesitter.get_parser(bufnr3, "lua")
    parser3:parse()
    local root3 = parser3:trees()[1]:root()
    local scope3 = location._find_innermost_scope(root3, 1, bufnr3)
    local ft3 = scope3:type()

    local loc3 = location._make_location("huginn_test_resolve_amb.lua", { ft3 .. "|dupe" })
    local res3, err3 = location.resolve("/tmp", loc3)
    assert_nil(err3)
    assert_equal("ambiguous", res3[ft3 .. "|dupe"].result)
    vim.api.nvim_buf_delete(bufnr3, { force = true })
end

local function test_from_nodes()
    -- nil and empty produce file-scoped locations
    local loc1 = location.from_nodes("src/main.lua", nil, 0)
    assert_equal("src/main.lua", loc1.filepath)
    assert_equal(0, #loc1.reference)

    local loc2 = location.from_nodes("src/main.lua", {}, 0)
    assert_equal(0, #loc2.reference)

    if not has_ts_parser then return end

    -- Valid nodes produce correct references
    local lines = { "local function my_func()", "  return 1", "end" }
    local bufnr, root = make_lua_buffer(lines)

    local nodes = {}
    for child in root:iter_children() do
        if location._is_named_scope(child) and location._get_symbol(child, bufnr) then
            table.insert(nodes, child)
        end
    end
    assert_true(#nodes > 0, "should find at least one scope node")

    local loc3 = location.from_nodes("src/main.lua", nodes, bufnr)
    assert_equal("src/main.lua", loc3.filepath)
    assert_equal(#nodes, #loc3.reference)
    assert_match("my_func", loc3.reference[1])

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

local function test_find_all_scopes()
    -- file not found
    local scopes, err = location.find_all_scopes("/nonexistent", "no_such_file.lua")
    assert_nil(scopes, "should return nil for missing file")
    assert_match("file not found", err)

    if not has_ts_parser then return end

    -- single function: one scope
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({
        "local function only_func()",
        "  return 1",
        "end",
    }, dir .. "/single.lua")

    scopes, err = location.find_all_scopes(dir, "single.lua")
    assert_nil(err, "should not error on valid file")
    assert_equal(1, #scopes, "should find one scope")
    assert_equal("only_func", location._get_symbol(scopes[1], table.concat(vim.fn.readfile(dir .. "/single.lua"), "\n")))

    -- multiple functions: all found
    vim.fn.writefile({
        "local function func_a()",
        "  return 1",
        "end",
        "",
        "local function func_b()",
        "  return 2",
        "end",
        "",
        "local x = 42",
    }, dir .. "/multi.lua")

    scopes, err = location.find_all_scopes(dir, "multi.lua")
    assert_nil(err)
    assert_equal(2, #scopes, "should find two scopes, not the plain variable")

    -- nested functions: both outer and inner returned
    vim.fn.writefile({
        "local function outer()",
        "  local function inner()",
        "    return 1",
        "  end",
        "  return inner()",
        "end",
    }, dir .. "/nested.lua")

    scopes, err = location.find_all_scopes(dir, "nested.lua")
    assert_nil(err)
    assert_equal(2, #scopes, "should find both outer and inner")

    -- no scopes: file with only assignments
    vim.fn.writefile({
        "local x = 1",
        "local y = 2",
    }, dir .. "/noscope.lua")

    scopes, err = location.find_all_scopes(dir, "noscope.lua")
    assert_nil(err)
    assert_equal(0, #scopes, "should find no scopes")

    -- prefers buffer parser when file is loaded
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "local function buf_func()",
        "  return 99",
        "end",
    })
    vim.bo[bufnr].filetype = "lua"
    vim.api.nvim_buf_set_name(bufnr, dir .. "/buffered.lua")
    -- file on disk has different content (no functions)
    vim.fn.writefile({ "local x = 1" }, dir .. "/buffered.lua")

    scopes, err = location.find_all_scopes(dir, "buffered.lua")
    assert_nil(err)
    assert_equal(1, #scopes, "should use buffer content, not disk")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(dir, "rf")
end

local function test_c_scope_detection()
    if not has_c_parser then return end

    local lines = {
        "int add(int a, int b) {",
        "    return a + b;",
        "}",
        "",
        "void do_nothing(void) {",
        "}",
        "",
        "int main(int argc, char **argv) {",
        "    int result = add(1, 2);",
        "    return 0;",
        "}",
    }
    local bufnr, root = make_lang_buffer(lines, "c")

    -- Should detect all three functions
    local symbols = collect_scope_symbols(root, bufnr)
    assert_equal(3, #symbols, "should find three C functions")
    assert_equal("add", symbols[1])
    assert_equal("do_nothing", symbols[2])
    assert_equal("main", symbols[3])

    -- Innermost scope inside add()
    local scope = location._find_innermost_scope(root, 1, bufnr)
    assert_not_nil(scope, "should find scope inside add()")
    assert_equal("add", location._get_symbol(scope, bufnr))

    -- Innermost scope inside main()
    local scope_main = location._find_innermost_scope(root, 8, bufnr)
    assert_not_nil(scope_main, "should find scope inside main()")
    assert_equal("main", location._get_symbol(scope_main, bufnr))

    -- Outside any function
    local scope_none = location._find_innermost_scope(root, 3, bufnr)
    assert_nil(scope_none, "should not find scope on blank line between functions")

    -- Function signature line should resolve to function_definition, not function_declarator
    local scope_sig = location._find_innermost_scope(root, 0, bufnr)
    assert_not_nil(scope_sig, "should find scope at function signature")
    assert_match("function_definition", scope_sig:type(), "signature should resolve to function_definition")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

local function test_go_scope_detection()
    if not has_go_parser then return end

    local lines = {
        "package main",
        "",
        "func add(a, b int) int {",
        "    return a + b",
        "}",
        "",
        "func main() {",
        "    _ = add(1, 2)",
        "}",
    }
    local bufnr, root = make_lang_buffer(lines, "go")

    -- Should detect both functions
    local symbols = collect_scope_symbols(root, bufnr)
    assert_equal(2, #symbols, "should find two Go functions")
    assert_equal("add", symbols[1])
    assert_equal("main", symbols[2])

    -- Innermost scope inside add()
    local scope = location._find_innermost_scope(root, 3, bufnr)
    assert_not_nil(scope, "should find scope inside add()")
    assert_equal("add", location._get_symbol(scope, bufnr))

    -- Outside any function
    local scope_none = location._find_innermost_scope(root, 1, bufnr)
    assert_nil(scope_none, "should not find scope on blank line outside functions")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

local function test_javascript_scope_detection()
    if not has_js_parser then return end

    local lines = {
        "function add(a, b) {",
        "    return a + b;",
        "}",
        "",
        "class Calculator {",
        "    multiply(a, b) {",
        "        return a * b;",
        "    }",
        "}",
    }
    local bufnr, root = make_lang_buffer(lines, "javascript")

    -- Should detect function, class, and method
    local found = {}
    local symbols = collect_scope_symbols(root, bufnr)
    for _, s in ipairs(symbols) do
        found[s] = true
    end
    assert_true(found["add"], "should find function add")
    assert_true(found["Calculator"], "should find class Calculator")
    assert_true(found["multiply"], "should find method multiply")

    -- Innermost scope inside add()
    local scope = location._find_innermost_scope(root, 1, bufnr)
    assert_not_nil(scope, "should find scope inside add()")
    assert_equal("add", location._get_symbol(scope, bufnr))

    -- Innermost scope inside multiply() should be multiply, not Calculator
    local scope_mul = location._find_innermost_scope(root, 6, bufnr)
    assert_not_nil(scope_mul, "should find scope inside multiply()")
    assert_equal("multiply", location._get_symbol(scope_mul, bufnr))

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

function M.run()
    local runner = TestRunner.new("location")

    runner:test("ref helpers: make_ref, parse_ref", test_ref_helpers)
    runner:test("serialize and deserialize: round-trip, errors, malformed references", test_serialize_and_deserialize)
    runner:test("scope detection and innermost scope resolution", test_scope_detection_and_innermost_scope)
    runner:test("from_context: normal mode, visual mode, and error cases", test_from_context_normal_and_visual)
    runner:test("resolve: found, not_found, ambiguous, file-scoped, errors", test_resolve_found_not_found_ambiguous)
    runner:test("from_nodes: empty, nil, and valid nodes", test_from_nodes)
    runner:test("find_all_scopes: error cases, single, multiple, nested, empty, buffer preference", test_find_all_scopes)
    runner:test("C: scope detection, innermost scope, declarator exclusion", test_c_scope_detection)
    runner:test("Go: scope detection and innermost scope", test_go_scope_detection)
    runner:test("JavaScript: functions, classes, methods, and innermost scope", test_javascript_scope_detection)

    runner:run()
end

return M
