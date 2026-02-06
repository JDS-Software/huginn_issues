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

-- filepath.lua
-- Walk filesystem to find .huginn files, handle relative/absolute paths


local M = {}

--- Private fallback implementation for path normalization
---@param path string path to normalize
---@return string normalized normalized path
local function huginn_normalize(path)
    -- Replace backslashes with forward slashes
    path = path:gsub("\\", "/")
    -- Remove duplicate slashes
    path = path:gsub("/+", "/")
    -- Handle relative path components
    local parts = {}
    local is_absolute = path:sub(1, 1) == "/"
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            if #parts > 0 and parts[#parts] ~= ".." then
                table.remove(parts)
            elseif not is_absolute then
                table.insert(parts, "..")
            end
        elseif part ~= "." then
            table.insert(parts, part)
        end
    end
    local result = table.concat(parts, "/")
    if is_absolute then
        result = "/" .. result
    end
    return result ~= "" and result or "."
end

-- Check vim.fs.normalize availability once at module load time
if vim and vim.fs and vim.fs.normalize then
    --- Normalize path (resolve .., ., remove double slashes)
    ---@param path string path to normalize
    ---@return string normalized normalized path
    function M.normalize(path)
        if not path or path == "" then
            return "."
        end
        return vim.fs.normalize(path)
    end
else
    --- Normalize path (resolve .., ., remove double slashes)
    ---@param path string path to normalize
    ---@return string normalized normalized path
    function M.normalize(path)
        if not path or path == "" then
            return "."
        end
        return huginn_normalize(path)
    end
end

--- Join path components (handles trailing slashes)
---@param ... string path components
---@return string joined joined path
function M.join(...)
    local args = { ... }
    if #args == 0 then
        return "."
    end

    local parts = {}
    for _, part in ipairs(args) do
        if part and part ~= "" then
            -- Special case: preserve root directory "/"
            if part == "/" then
                table.insert(parts, "/")
            else
                -- Remove trailing slashes
                part = part:gsub("/+$", "")
                if part ~= "" then
                    table.insert(parts, part)
                end
            end
        end
    end

    return M.normalize(table.concat(parts, "/"))
end

--- Get directory name from path
---@param path string file path
---@return string dir parent directory
function M.dirname(path)
    if not path or path == "" then
        return "."
    end

    path = M.normalize(path)

    -- Special case: root directory should return itself
    if path == "/" then
        return "/"
    end

    -- Remove trailing slash
    path = path:gsub("/+$", "")

    -- Find last slash
    local last_slash = path:match("^.*()/")

    if not last_slash then
        return "."
    end

    local dir = path:sub(1, last_slash - 1)
    return dir ~= "" and dir or "/"
end

--- Get file name from path
---@param path string file path
---@return string name filename
function M.basename(path)
    if not path or path == "" then
        return ""
    end

    path = M.normalize(path)

    -- Remove trailing slash
    path = path:gsub("/+$", "")

    -- Get everything after last slash
    return path:match("[^/]+$") or path
end

--- Check if path exists (file or directory)
---@param path string path to check
---@return boolean exists
function M.exists(path)
    if not path or path == "" then
        return false
    end

    -- Use vim.uv (libuv) for filesystem operations
    local stat = vim.uv.fs_stat(path)
    return stat ~= nil
end

--- Check if path is a directory
---@param path string path to check
---@return boolean is_dir
function M.is_directory(path)
    if not path or path == "" then
        return false
    end

    local stat = vim.uv.fs_stat(path)
    return stat ~= nil and stat.type == "directory"
end

--- Find nearest .huginn file by walking up from given path
---@param start_path string absolute path to start searching from
---@return string? huginn_path absolute path to .huginn file, or nil if not found
function M.find_huginn_file(start_path)
    if not start_path or start_path == "" then
        return nil
    end

    -- Normalize and ensure absolute path
    local current = M.normalize(start_path)

    -- If start_path is a file, start from its directory
    if not M.is_directory(current) then
        current = M.dirname(current)
    end

    -- Walk up the directory tree
    local previous = nil
    while current ~= previous do
        local huginn_path = M.join(current, ".huginn")

        if M.exists(huginn_path) then
            return huginn_path
        end

        -- Move up one directory
        previous = current
        current = M.dirname(current)
    end

    return nil
end

--- Convert relative path to absolute based on .huginn directory
---@param relative string relative path
---@param huginn_dir string absolute path to directory containing .huginn
---@return string? absolute absolute path, or nil if inputs are empty
function M.relative_to_absolute(relative, huginn_dir)
    if not relative or relative == "" then
        return nil
    end

    if not huginn_dir or huginn_dir == "" then
        return nil
    end

    -- If already absolute, return as-is
    if relative:sub(1, 1) == "/" then
        return M.normalize(relative)
    end

    return M.join(huginn_dir, relative)
end

--- Convert absolute path to relative based on .huginn directory
--- Returns absolute path on failure
---@param absolute string absolute path
---@param huginn_dir string absolute path to directory containing .huginn
---@return string? relative relative path, or nil if inputs are empty
function M.absolute_to_relative(absolute, huginn_dir)
    if not absolute or absolute == "" then
        return nil
    end

    if not huginn_dir or huginn_dir == "" then
        return nil
    end

    -- Normalize both paths
    absolute = M.normalize(absolute)
    huginn_dir = M.normalize(huginn_dir)

    -- Ensure huginn_dir ends without slash for consistent comparison
    huginn_dir = huginn_dir:gsub("/+$", "")

    -- Check if absolute path starts with huginn_dir
    local prefix = huginn_dir .. "/"
    if absolute:sub(1, #prefix) == prefix then
        -- Remove the prefix to get relative path
        return absolute:sub(#prefix + 1)
    elseif absolute == huginn_dir then
        return "."
    else
        return absolute
    end
end

return M
