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

-- ini_parser.lua
-- Parse .huginn INI-style configuration files


local filepath = require("huginn.modules.filepath")

local M = {}

--- Parse a string value, converting to boolean or number if appropriate
---@param value string raw string value
---@return string|number|boolean parsed value (boolean for true/false, number if matches int/float pattern)
local function parse_value(value)
    -- Check for boolean values
    if value == "true" then return true end
    if value == "false" then return false end
    -- Check for integer pattern: one or more digits
    if value:match("^[0-9]+$") then
        return tonumber(value)
    end
    -- Check for float pattern: digits, dot, digits
    if value:match("^[0-9]+%.[0-9]+$") then
        return tonumber(value)
    end
    return value
end

--- Extract value from the right side of a key=value line
---@param rhs string everything after the '='
---@return string|number|boolean|nil value parsed value, or nil if empty
local function extract_value(rhs)
    -- Trim leading whitespace
    rhs = rhs:match("^%s*(.*)$") or ""

    if rhs == "" then
        return nil
    end

    -- Check for quoted value
    if rhs:sub(1, 1) == '"' then
        -- Find closing quote
        local closing = rhs:find('"', 2, true)
        if closing then
            local quoted = rhs:sub(2, closing - 1)
            return parse_value(quoted)
        end
        -- No closing quote - treat rest as value (minus the opening quote)
        return parse_value(rhs:sub(2))
    end

    -- Unquoted value: take first word (up to whitespace)
    local word = rhs:match("^(%S+)")
    if word then
        return parse_value(word)
    end

    return nil
end

--- Serialize a Lua value to its INI string representation
--- Note: strings matching boolean ("true"/"false") or number patterns cannot
--- round-trip as strings because the parser coerces them unconditionally.
--- Strings containing embedded double quotes will not round-trip correctly.
---@param value boolean|number|string the value to serialize
---@return string serialized the INI-formatted value string
local function serialize_value(value)
    local vtype = type(value)
    if vtype == "boolean" then
        return value and "true" or "false"
    elseif vtype == "number" then
        return tostring(value)
    elseif vtype == "string" then
        if value == "" or value:find(" ") then
            return '"' .. value .. '"'
        end
        return value
    end
    return tostring(value)
end

--- Parse a .huginn configuration string
---@param content string raw file content
---@return table<string, table<string, any>> config parsed configuration as section -> key -> value
function M.parse(content)
    local config = {}
    local current_section = nil

    for line in content:gmatch("[^\r\n]*") do
        -- Trim leading whitespace for checks
        local trimmed = line:match("^%s*(.*)$") or ""

        -- Skip empty lines
        if trimmed == "" then
            goto continue
        end

        -- Skip comment lines (# as first non-whitespace)
        if trimmed:sub(1, 1) == "#" then
            goto continue
        end

        -- Check for section header [SectionName]
        local section = trimmed:match("^%[([^%]]+)%]")
        if section then
            current_section = section
            if not config[current_section] then
                config[current_section] = {}
            end
            goto continue
        end

        -- Parse key = value (only if we have a current section)
        if current_section then
            local key, rhs = trimmed:match("^(%S+)%s*=%s*(.*)$")
            if key and rhs then
                local value = extract_value(rhs)
                if value ~= nil then
                    -- Check if key is an aggregating key (ends with [])
                    if key:sub(-2) == "[]" then
                        local base_key = key
                        if not config[current_section][base_key] then
                            config[current_section][base_key] = {}
                        end
                        table.insert(config[current_section][base_key], value)
                    else
                        -- Normal key: last value wins
                        config[current_section][key] = value
                    end
                end
            end
        end

        ::continue::
    end

    return config
end

--- Serialize a configuration table to INI-format string
--- Round-trip: parse(serialize(data)) produces an equivalent table, with the
--- known limitation that string values matching boolean/number patterns will
--- be coerced to their respective types on re-parse.
---@param data table<string, table<string, any>> section -> key -> value configuration
---@param section_order string[]? optional ordered list of section names; unlisted sections appended alphabetically
---@return string content the serialized INI string
function M.serialize(data, section_order)
    if not data then
        return ""
    end

    local lines = {}

    -- Build ordered section list
    local ordered = {}
    local seen = {}

    if section_order then
        for _, name in ipairs(section_order) do
            if data[name] then
                table.insert(ordered, name)
                seen[name] = true
            end
        end
    end

    -- Collect remaining sections, sorted alphabetically for determinism
    local remaining = {}
    for name, _ in pairs(data) do
        if not seen[name] then
            table.insert(remaining, name)
        end
    end
    table.sort(remaining)
    for _, name in ipairs(remaining) do
        table.insert(ordered, name)
    end

    if #ordered == 0 then
        return ""
    end

    -- Serialize each section
    for i, section_name in ipairs(ordered) do
        local section = data[section_name]

        table.insert(lines, "[" .. section_name .. "]")

        -- Sort keys alphabetically for determinism
        local keys = {}
        for key, _ in pairs(section) do
            table.insert(keys, key)
        end
        table.sort(keys)

        for _, key in ipairs(keys) do
            local value = section[key]
            if value ~= nil then
                if type(value) == "table" then
                    -- Aggregating key: emit one line per array element
                    for _, elem in ipairs(value) do
                        table.insert(lines, key .. " = " .. serialize_value(elem))
                    end
                else
                    table.insert(lines, key .. " = " .. serialize_value(value))
                end
            end
        end

        -- Blank line between sections (not after the last)
        if i < #ordered then
            table.insert(lines, "")
        end
    end

    return table.concat(lines, "\n") .. "\n"
end

--- Parse a .huginn configuration file
---@param path string path to .huginn file
---@return table<string, table<string, any>>|nil config parsed configuration, or nil on error
---@return string|nil error error message if failed
function M.parse_file(path)
    if not path or path == "" then
        return nil, "No filepath provided"
    end

    path = filepath.normalize(path)

    local ok, content = pcall(vim.fn.readfile, path)
    if not ok then
        return nil, "File does not exist: " .. path
    end
    return M.parse(table.concat(content, "\n")), nil
end

return M
