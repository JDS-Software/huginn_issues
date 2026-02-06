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

-- config.lua
-- Configuration lifecycle: defaults, loading, merging, reloading


local ini_parser = require("huginn.modules.ini_parser")
local filepath = require("huginn.modules.filepath")
local logging = require("huginn.modules.logging")

local function is_boolean(value)
    return type(value) == "boolean"
end

local function is_string(value, opts)
    if type(value) ~= "string" then return false end
    if opts and opts.pattern and not value:match(opts.pattern) then return false end
    return true
end

local function is_integer(value, opts)
    if type(value) ~= "number" or value ~= math.floor(value) then return false end
    if opts then
        if opts.min and value < opts.min then return false end
        if opts.max and value > opts.max then return false end
    end
    return true
end

--- Serialize a Lua default to an INI-compatible string
--- Strings containing #, whitespace, or matching boolean/number patterns get quoted
--- so the INI parser round-trips them correctly.
---@param value boolean|number|string the value to format
---@return string formatted the INI-formatted value string
local function format_value(value)
    if type(value) ~= "string" then return tostring(value) end
    if value:find("#") or value:find("%s")
        or value == "true" or value == "false"
        or value:match("^[0-9]+$") or value:match("^[0-9]+%.[0-9]+$") then
        return '"' .. value .. '"'
    end
    return value
end

local M = {}


---@class huginn.ConfigOption
---@field name string
---@field default boolean|number|string
---@field validate fun(value: any, opts?: table): boolean
---@field opts? table duck-typed params passed to validate (e.g. { min, max })

---@class huginn.ConfigSection
---@field load_default boolean whether this section is loaded at runtime
---@field options huginn.ConfigOption[]

-- Section definitions keyed by header name
---@type table<string, huginn.ConfigSection>
local sections = {
    annotation = {
        load_default = true,
        options = {
            { name = "enabled",    default = true,      validate = is_boolean },
            { name = "background", default = "#ffffff", validate = is_string, opts = { pattern = "^#%x%x%x%x%x%x$" } },
            { name = "foreground", default = "#000000", validate = is_string, opts = { pattern = "^#%x%x%x%x%x%x$" } },
        },
    },
    plugin = {
        load_default = true,
        options = {
            { name = "issue_dir", default = "issues", validate = is_string },
        },
    },
    index = {
        load_default = true,
        options = {
            { name = "key_length", default = 16, validate = is_integer, opts = { min = 16, max = 64 } },
        },
    },
    issue = {
        load_default = true,
        options = {
            { name = "open_after_create", default = false, validate = is_boolean },
        },
    },
    show = {
        load_default = true,
        options = {
            { name = "description_length", default = 80, validate = is_integer, opts = { min = 1 } },
        },
    },
    logging = {
        load_default = true,
        options = {
            { name = "enabled",  default = false,        validate = is_boolean },
            { name = "filepath", default = ".huginnlog", validate = is_string },
        },
    },
}

-- Iteration order: plugin first, then remaining sections alphabetized.
-- Computed once from the sections table keys.
local section_order
do
    section_order = vim.tbl_keys(sections)
    table.sort(section_order)
    for i, key in ipairs(section_order) do
        if key == "plugin" then
            table.remove(section_order, i)
            break
        end
    end
    table.insert(section_order, 1, "plugin")
end

--- Find the option definition for a given section and key.
---@param section_name string the INI section name
---@param key string the option key
---@return huginn.ConfigOption|nil opt the option definition, or nil if not found
local function find_option(section_name, key)
    local entry = sections[section_name]
    if not entry or not entry.load_default then return nil end
    for _, opt in ipairs(entry.options) do
        if opt.name == key then return opt end
    end
    return nil
end

--- Merged active configuration, accessible as config.active.section.key
---@type table<string, table<string, any>>
M.active = {}

--- Absolute path to the loaded .huginn file
---@type string|nil
M.huginn_path = nil

-- Memoized parsed defaults (private, never mutated after creation)
local parsed_defaults = nil

--- Materialize sections into an INI string.
--- When commented is true, all sections are included with values prefixed by "# "
--- and non-loadable sections get an explanatory comment (for HuginnInit).
--- When commented is false, only load_default sections are emitted with bare
--- values (for parsing into runtime defaults).
---@param commented boolean whether to comment out values
---@return string ini_content the materialized INI string
local function materialize_defaults(commented)
    local lines = {}
    local first = true

    for _, header in ipairs(section_order) do
        local entry = sections[header]

        if not commented and not entry.load_default then
            goto continue
        end

        if not first then
            table.insert(lines, "")
        end
        first = false

        table.insert(lines, "[" .. header .. "]")

        if commented and not entry.load_default then
            table.insert(lines,
                "# " .. header .. " is not loaded by default. The values below are for example only.")
        end

        local prefix = commented and "# " or ""
        for _, opt in ipairs(entry.options) do
            table.insert(lines, prefix .. opt.name .. " = " .. format_value(opt.default))
        end

        ::continue::
    end

    return table.concat(lines, "\n") .. "\n"
end

--- Validate a parsed config table against section definitions.
--- Warns on any default that fails its own validator (programming error).
---@param parsed table<string, table<string, any>> the parsed config
local function validate_defaults(parsed)
    for _, header in ipairs(section_order) do
        local entry = sections[header]
        if not entry.load_default then goto continue end
        local section = parsed[header]
        if not section then goto continue end

        for _, opt in ipairs(entry.options) do
            local value = section[opt.name]
            if value ~= nil and not opt.validate(value, opt.opts) then
                vim.notify(
                    "huginn: default value failed validation for ["
                    .. header .. "] " .. opt.name .. ": " .. tostring(value),
                    vim.log.levels.WARN
                )
            end
        end

        ::continue::
    end
end

--- Return a deep copy of parsed defaults, parsing on first call.
--- The memoized original is never handed out directly, so callers can safely mutate.
---@return table<string, table<string, any>> defaults fresh copy of section -> key -> value
local function get_defaults()
    if not parsed_defaults then
        parsed_defaults = ini_parser.parse(materialize_defaults(false))
        validate_defaults(parsed_defaults)
    end
    return vim.deepcopy(parsed_defaults, false)
end

--- Generate the full default .huginn file content as a string
--- All sections are included with values shown as comments.
--- Sections with load_default=false get an explanatory comment.
---@return string content the default .huginn file content
function M.generate_default_file()
    return materialize_defaults(true)
end

--- Load configuration from a .huginn file and merge with defaults
--- User values take precedence over defaults. Invalid values generate warnings
--- and fall back to the default. Unknown keys within known sections are discarded.
--- Populates M.active and M.huginn_path on success.
---@param huginn_path string absolute path to the .huginn file
---@param external_logger huginn.Logger? optional logger for reporting warnings
---@return table<string, table<string, any>>|nil config the merged active config, or nil on error
---@return string|nil error error message if loading failed
function M.load(huginn_path, external_logger)
    if not huginn_path or huginn_path == "" then
        return nil, "No .huginn path provided"
    end

    if M.active and M.huginn_path == huginn_path then
        return M.active
    end

    local logger
    if external_logger then
        logger = external_logger
    else
        logger = logging.new(false, ".huginnlog")
    end

    local defaults = get_defaults()

    local user_config, err = ini_parser.parse_file(huginn_path)
    if not user_config then
        return nil, err
    end

    M.huginn_path = filepath.normalize(huginn_path)

    for section, user_keys in pairs(user_config) do
        if not defaults[section] then
            logger:alert("WARN", "Unknown config section: [" .. section .. "]")
        else
            for key, value in pairs(user_keys) do
                local opt = find_option(section, key)
                if not opt then
                    logger:alert("WARN", "Unknown config key: [" .. section .. "] " .. key)
                elseif not opt.validate(value, opt.opts) then
                    logger:alert("WARN",
                        "Invalid value for [" .. section .. "] " .. key
                        .. ": " .. tostring(value) .. " (using default: " .. tostring(opt.default) .. ")")
                else
                    defaults[section][key] = value
                end
            end
        end
    end

    M.active = defaults
    return M.active, nil
end

--- Reload the current .huginn configuration, bypassing the cache
---@param logger huginn.Logger? optional logger for reload warnings
---@return table<string, table<string, any>>|nil config the fresh config, or nil on error
---@return string|nil error error message if reload failed
function M.reload(logger)
    if not M.huginn_path then
        return nil, "No .huginn file loaded"
    end
    local path = M.huginn_path
    M.huginn_path = nil
    return M.load(path, logger)
end

return M
