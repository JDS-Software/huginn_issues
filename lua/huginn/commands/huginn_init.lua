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

-- huginn_init.lua
-- HuginnInit command: create or replace a .huginn configuration file


local context = require("huginn.modules.context")
local config = require("huginn.modules.config")
local filepath = require("huginn.modules.filepath")
local confirm = require("huginn.components.confirm")

local M = {}

--- Write the default .huginn file, reinitialize the plugin, and open the file
---@param huginn_path string absolute path to write the .huginn file
---@param logger huginn.Logger
local function write_and_open(huginn_path, logger)
    local content = config.generate_default_file()
    local lines = vim.split(content, "\n", { trimempty = false })
    -- vim.split on trailing \n produces an empty final element; drop it
    if lines[#lines] == "" then
        table.remove(lines)
    end

    local ok, result = pcall(vim.fn.writefile, lines, huginn_path)
    if not ok or result == -1 then
        logger:alert("ERROR", "Failed to write .huginn file: " .. huginn_path)
        return
    end

    -- Reset and reinitialize
    context._reset()
    config.huginn_path = nil

    local ctx, err = context.init(nil, logger)
    if ctx then
        context.setup(logger)
        logger:log("INFO", "Huginn initialized: " .. ctx.cwd)
    else
        logger:alert("WARN", "Config written but initialization failed: " .. (err or "unknown error"))
    end

    vim.cmd("edit " .. vim.fn.fnameescape(huginn_path))
end

--- Execute the HuginnInit command
---@param logger huginn.Logger
function M.execute(logger)
    local ctx = context.get()

    if ctx then
        confirm.show({
            message = "A .huginn configuration already exists. Replace it?",
            level = "caution",
        }, function(confirmed)
            if confirmed then
                write_and_open(config.huginn_path, logger)
            end
        end)
    else
        local cwd = vim.fn.getcwd()
        local huginn_path = filepath.join(cwd, ".huginn")
        write_and_open(huginn_path, logger)
    end
end

return M
