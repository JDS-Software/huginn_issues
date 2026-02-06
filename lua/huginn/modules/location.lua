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

-- location.lua
-- Bridge between source code positions, tree-sitter structural data, and
-- serializable Location objects.


local ini_parser = require("huginn.modules.ini_parser")
local filepath = require("huginn.modules.filepath")

local M = {}

-- Scope type patterns — substring matches against tree-sitter node types
local scope_patterns = {
    "function",
    "method",
    "class",
}

-- Patterns that disqualify a node even if it matches a scope pattern
local scope_exclude_patterns = {
    "call",
    "invocation",
    "function_declarator",
}

---@class huginn.Location
---@field filepath string path relative to context.cwd
---@field reference string[] array of "type|symbol" strings

--- Construct a Location instance
---@param rel_filepath string path relative to context.cwd
---@param references string[]? array of "type|symbol" strings
---@return huginn.Location
local function make_location(rel_filepath, references)
    return {
        filepath = rel_filepath,
        reference = references or {},
    }
end

--- Build a "type|symbol" reference string
---@param node_type string tree-sitter node type
---@param symbol string construct name
---@return string ref "type|symbol"
local function make_ref(node_type, symbol)
    return node_type .. "|" .. symbol
end

--- Split a reference string on the first "|"
---@param ref_string string "type|symbol" reference
---@return string? node_type
---@return string? symbol
local function parse_ref(ref_string)
    local pipe = ref_string:find("|", 1, true)
    if not pipe then
        return nil, nil
    end
    return ref_string:sub(1, pipe - 1), ref_string:sub(pipe + 1)
end

--- Check if a node is a variable declaration/assignment whose value is a function
---@param node userdata TSNode
---@return boolean
local function is_variable_with_function(node)
    local ntype = node:type()
    if not (ntype:find("variable") or ntype:find("assignment") or ntype:find("lexical_declaration")) then
        return false
    end
    local value_nodes = node:field("value")
    if not value_nodes or #value_nodes == 0 then
        return false
    end
    for _, v in ipairs(value_nodes) do
        local vtype = v:type()
        if vtype:find("function") or vtype:find("arrow") then
            return true
        end
    end
    return false
end

--- Check if a node represents a named scope
---@param node userdata TSNode
---@return boolean
local function is_named_scope(node)
    local ntype = node:type()
    for _, pattern in ipairs(scope_exclude_patterns) do
        if ntype:find(pattern) then
            return false
        end
    end
    for _, pattern in ipairs(scope_patterns) do
        if ntype:find(pattern) then
            return true
        end
    end
    return is_variable_with_function(node)
end

--- Extract the symbol name from a tree-sitter node
---@param node userdata TSNode
---@param source integer|string buffer number or source string
---@return string? symbol
local function get_symbol(node, source)
    local name_nodes = node:field("name")
    if name_nodes and #name_nodes > 0 then
        return vim.treesitter.get_node_text(name_nodes[1], source)
    end
    -- C/C++ style: function name is nested in a declarator chain
    -- e.g. function_definition -> function_declarator -> identifier
    local decl_nodes = node:field("declarator")
    if decl_nodes and #decl_nodes > 0 then
        local decl = decl_nodes[1]
        while decl do
            if decl:type() == "identifier" then
                return vim.treesitter.get_node_text(decl, source)
            end
            local inner_name = decl:field("name")
            if inner_name and #inner_name > 0 then
                return vim.treesitter.get_node_text(inner_name[1], source)
            end
            local inner = decl:field("declarator")
            if inner and #inner > 0 then
                decl = inner[1]
            else
                break
            end
        end
    end
    return nil
end

--- Find the innermost named scope enclosing a given line (0-indexed)
---@param node userdata TSNode root or subtree node
---@param line integer 0-indexed line number
---@param source integer|string buffer number or source string
---@return userdata? TSNode innermost scope node, or nil
local function find_innermost_scope(node, line, source)
    for child in node:iter_children() do
        local start_row, _, end_row, _ = child:range()
        if start_row <= line and end_row >= line then
            local deeper = find_innermost_scope(child, line, source)
            if deeper then
                return deeper
            end
            if is_named_scope(child) and get_symbol(child, source) then
                return child
            end
        end
    end
    if is_named_scope(node) and get_symbol(node, source) then
        return node
    end
    return nil
end

--- Collect all nodes matching a given type and symbol name
---@param node userdata TSNode root
---@param ntype string tree-sitter node type (exact match)
---@param symbol string symbol name (exact match)
---@param source integer|string buffer number or source string
---@return userdata[] matches array of matching TSNodes
local function find_nodes_by_type_and_symbol(node, ntype, symbol, source)
    local matches = {}
    local function walk(n)
        if n:type() == ntype and get_symbol(n, source) == symbol then
            table.insert(matches, n)
        end
        for child in n:iter_children() do
            walk(child)
        end
    end
    walk(node)
    return matches
end

--- Extract the root node from a parsed tree-sitter parser
---@param parser userdata tree-sitter parser
---@return userdata? root TSNode
---@return string? error
local function parse_root(parser)
    local ok, _ = pcall(parser.parse, parser)
    if not ok then return nil, "tree-sitter parse failed" end
    local trees = parser:trees()
    if not trees or #trees == 0 then
        return nil, "tree-sitter parse returned no trees"
    end
    return trees[1]:root(), nil
end

--- Get tree-sitter root + source from a loaded buffer
---@param bufnr integer buffer number
---@return userdata? root TSNode
---@return integer|nil source buffer number
---@return string? error
local function tree_from_buffer(bufnr)
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
    if not ok or not parser then
        return nil, nil, "no tree-sitter parser available"
    end
    local root, err = parse_root(parser)
    if not root then return nil, nil, err end
    return root, bufnr, nil
end

--- Get tree-sitter root + source by reading a file from disk
---@param abs_path string absolute file path
---@param rel_filepath string relative path (for error messages)
---@return userdata? root TSNode
---@return string|nil source file content
---@return string? error
local function tree_from_disk(abs_path, rel_filepath)
    local ok, lines = pcall(vim.fn.readfile, abs_path)
    if not ok then
        return nil, nil, "file not found: " .. rel_filepath
    end
    local content = table.concat(lines, "\n")
    local lang = vim.filetype.match({ filename = abs_path })
    if not lang then
        return nil, nil, "no tree-sitter parser available"
    end
    local ok, parser = pcall(vim.treesitter.get_string_parser, content, lang)
    if not ok or not parser then
        return nil, nil, "no tree-sitter parser available"
    end
    local root, err = parse_root(parser)
    if not root then return nil, nil, err end
    return root, content, nil
end

--- Acquire a tree-sitter root and source for a file.
--- Uses the buffer parser when the file is loaded, otherwise reads from disk.
---@param abs_path string absolute file path
---@param rel_filepath string relative path (for error messages)
---@return userdata? root TSNode
---@return integer|string|nil source buffer number or file content
---@return string? error
local function acquire_tree(abs_path, rel_filepath)
    local bufnr = vim.fn.bufnr(abs_path)
    if bufnr ~= -1 then
        return tree_from_buffer(bufnr)
    end
    return tree_from_disk(abs_path, rel_filepath)
end

--- Walk a tree-sitter tree and collect all named scope nodes
---@param node userdata TSNode root
---@param source integer|string buffer number or source string
---@return userdata[] scopes array of TSNodes
local function collect_all_scopes(node, source)
    local scopes = {}
    local function walk(n)
        if is_named_scope(n) and get_symbol(n, source) then
            table.insert(scopes, n)
        end
        for child in n:iter_children() do
            walk(child)
        end
    end
    walk(node)
    return scopes
end

-- Expose internals for testing
M._make_location = make_location
M._parse_ref = parse_ref
M._make_ref = make_ref
M._is_named_scope = is_named_scope
M._get_symbol = get_symbol
M._find_innermost_scope = find_innermost_scope

--- Serialize a Location to INI-format string
---@param location huginn.Location
---@return string content INI-formatted string
function M.serialize(location)
    local data = {
        location = {
            filepath = location.filepath,
        },
    }
    if #location.reference > 0 then
        data.location["reference[]"] = location.reference
    end
    return ini_parser.serialize(data)
end

--- Deserialize an INI-format string into a Location
---@param content string INI-formatted location block
---@param logger huginn.Logger? optional logger for warnings
---@return huginn.Location? location
---@return string? error
function M.deserialize(content, logger)
    local parsed = ini_parser.parse(content)
    if not parsed.location then
        return nil, "missing [location] section"
    end
    if not parsed.location.filepath then
        return nil, "missing filepath in [location]"
    end

    local references = {}
    local raw_refs = parsed.location["reference[]"]
    if raw_refs then
        if type(raw_refs) ~= "table" then
            raw_refs = { raw_refs }
        end
        for _, ref in ipairs(raw_refs) do
            local t, s = parse_ref(ref)
            if t and s then
                table.insert(references, ref)
            else
                if logger then
                    logger:log("WARN", "malformed reference (no | delimiter): " .. tostring(ref))
                end
            end
        end
    end

    return make_location(parsed.location.filepath, references), nil
end

--- Build a Location from the current command context
---@param cmd_ctx huginn.CommandContext
---@return huginn.Location? location
---@return string? error
function M.from_context(cmd_ctx)
    if not cmd_ctx.window then
        return nil, "no window state available"
    end

    local ft = vim.bo[cmd_ctx.buffer].filetype
    local ok, parser = pcall(vim.treesitter.get_parser, cmd_ctx.buffer)
    if not ok or not parser then
        return nil, "no tree-sitter parser available for " .. ft
    end

    local rel_path = filepath.absolute_to_relative(cmd_ctx.window.filepath, cmd_ctx.cwd)

    local ok_parse, _ = pcall(parser.parse, parser)
    if not ok_parse then return nil, "tree-sitter parse failed" end
    local trees = parser:trees()
    if not trees or #trees == 0 then
        return nil, "tree-sitter parse returned no trees"
    end
    local root = trees[1]:root()

    local mode = cmd_ctx.window.mode
    if mode == "n" then
        local line = cmd_ctx.window.start.line - 1
        local scope = find_innermost_scope(root, line, cmd_ctx.buffer)
        if scope then
            return make_location(rel_path, { make_ref(scope:type(), get_symbol(scope, cmd_ctx.buffer)) }), nil
        end
        return make_location(rel_path, {}), nil
    end

    -- Visual modes: "v", "V", "\22" (block)
    local start_line = cmd_ctx.window.start.line - 1
    local finish_line = cmd_ctx.window.finish.line - 1
    local seen = {}
    local references = {}
    for line = start_line, finish_line do
        local scope = find_innermost_scope(root, line, cmd_ctx.buffer)
        if scope then
            local ref = make_ref(scope:type(), get_symbol(scope, cmd_ctx.buffer))
            if not seen[ref] then
                seen[ref] = true
                table.insert(references, ref)
            end
        end
    end

    return make_location(rel_path, references), nil
end

--- Resolve a Location against the current file state
---@param cwd string absolute path to context root
---@param location huginn.Location
---@return table<string, {result: string, node: userdata|nil}>? results
---@return string? error
function M.resolve(cwd, location)
    if #location.reference == 0 then
        return {}
    end

    local abs_path = filepath.join(cwd, location.filepath)

    local source
    local root
    local bufnr = vim.fn.bufnr(abs_path)

    if bufnr ~= -1 then
        local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
        if not ok or not parser then
            return nil, "no tree-sitter parser available"
        end
        local ok_parse, _ = pcall(parser.parse, parser)
        if not ok_parse then return nil, "tree-sitter parse failed" end
        local trees = parser:trees()
        if not trees or #trees == 0 then
            return nil, "tree-sitter parse returned no trees"
        end
        root = trees[1]:root()
        source = bufnr
    else
        local ok_read, lines = pcall(vim.fn.readfile, abs_path)
        if not ok_read then
            return nil, "file not found: " .. location.filepath
        end
        local content = table.concat(lines, "\n")
        local lang = vim.filetype.match({ filename = abs_path })
        if not lang then
            return nil, "no tree-sitter parser available"
        end
        local ok, parser = pcall(vim.treesitter.get_string_parser, content, lang)
        if not ok or not parser then
            return nil, "no tree-sitter parser available"
        end
        local ok_parse, _ = pcall(parser.parse, parser)
        if not ok_parse then return nil, "tree-sitter parse failed" end
        local trees = parser:trees()
        if not trees or #trees == 0 then
            return nil, "tree-sitter parse returned no trees"
        end
        root = trees[1]:root()
        source = content
    end

    local results = {}
    for _, ref in ipairs(location.reference) do
        local ntype, symbol = parse_ref(ref)
        if not ntype or not symbol then
            results[ref] = { result = "not_found", node = nil }
        else
            local matches = find_nodes_by_type_and_symbol(root, ntype, symbol, source)
            if #matches == 0 then
                results[ref] = { result = "not_found", node = nil }
            elseif #matches == 1 then
                results[ref] = { result = "found", node = matches[1] }
            else
                results[ref] = { result = "ambiguous", node = nil }
            end
        end
    end

    return results, nil
end

--- Build a Location from a relative filepath and an array of TSNodes
---@param rel_filepath string path relative to context root
---@param nodes userdata[]? array of TSNodes
---@param source integer|string buffer number or source string
---@return huginn.Location location
function M.from_nodes(rel_filepath, nodes, source)
    if not nodes or #nodes == 0 then
        return make_location(rel_filepath, {})
    end

    local references = {}
    for _, node in ipairs(nodes) do
        local sym = get_symbol(node, source)
        if sym then
            table.insert(references, make_ref(node:type(), sym))
        end
    end

    return make_location(rel_filepath, references)
end

--- Check if an issue is relevant to a set of cursor references.
--- File-scoped issues (no references) are always relevant.
--- Scoped issues match if any reference overlaps with the cursor's references.
---@param iss huginn.HuginnIssue
---@param cursor_refs table<string, boolean> set of reference strings at cursor
---@return boolean
function M.is_relevant(iss, cursor_refs)
    if not iss.location or #iss.location.reference == 0 then
        return true
    end
    for _, ref in ipairs(iss.location.reference) do
        if cursor_refs[ref] then
            return true
        end
    end
    return false
end

--- Parse a source file and return all named scope nodes.
---@param cwd string absolute path to context root
---@param rel_filepath string path relative to context root
---@return userdata[]? scopes array of TSNodes, or nil on error
---@return string? error
function M.find_all_scopes(cwd, rel_filepath)
    local abs_path = filepath.join(cwd, rel_filepath)
    local root, source, err = acquire_tree(abs_path, rel_filepath)
    if not root then return nil, err end
    return collect_all_scopes(root, source), nil
end

--- Parse a source file and return all named scopes as "type|symbol" reference strings.
---@param cwd string absolute path to context root
---@param rel_filepath string path relative to context root
---@return string[]|nil refs deduplicated "type|symbol" strings
---@return string|nil error
function M.find_all_scope_refs(cwd, rel_filepath)
    local abs_path = filepath.join(cwd, rel_filepath)
    local root, source, err = acquire_tree(abs_path, rel_filepath)
    if not root then return nil, err end

    local scopes = collect_all_scopes(root, source)
    local seen = {}
    local refs = {}
    for _, node in ipairs(scopes) do
        local sym = get_symbol(node, source)
        if sym then
            local ref = make_ref(node:type(), sym)
            if not seen[ref] then
                seen[ref] = true
                table.insert(refs, ref)
            end
        end
    end
    return refs, nil
end

return M
