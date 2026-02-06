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

-- logging.lua
-- Dependency-injected logging with internal buffer and file persistence


local M = {}

---@alias huginn.LogLevel "INFO" | "WARN" | "ERROR"

---@class huginn.Logger
---@field enabled boolean whether file persistence is active
---@field filepath string path to log output file
---@field buffer string[] internal log line buffer
---@field flushed_count integer number of lines already written to file
local Logger = {}
Logger.__index = Logger

--- Format a log line with local timestamp
---@param level huginn.LogLevel log level
---@param message string log message
---@return string formatted log line
local function format_line(level, message)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    return string.format("[%s] %s: %s", timestamp, level, message)
end

--- Create a new Logger instance
---@param enabled boolean whether to persist logs to file
---@param filepath string path to log file
---@return huginn.Logger
function M.new(enabled, filepath)
    local self = setmetatable({}, Logger)
    self.enabled = enabled or false
    self.filepath = filepath or ".huginnlog"
    self.buffer = {}
    self.flushed_count = 0

    if self.enabled then
        self:_setup_autocmds()
    end

    return self
end

--- Append a message to the internal log buffer
---@param level huginn.LogLevel log level
---@param message string log message
function Logger:log(level, message)
    local line = format_line(level, message)
    table.insert(self.buffer, line)
end

--- Show a message to the user and log it
---@param level huginn.LogLevel log level
---@param message string alert message
function Logger:alert(level, message)
    self:log(level, message)

    local hl
    if level == "ERROR" then
        hl = "ErrorMsg"
    elseif level == "WARN" then
        hl = "WarningMsg"
    else
        hl = "Normal"
    end

    vim.api.nvim_echo({ { "[Huginn] " .. message, hl } }, true, {})
end

--- Flush unflushed buffer lines to file
function Logger:flush()
    if not self.enabled then
        return
    end
    if self.flushed_count >= #self.buffer then
        return
    end

    local new_lines = {}
    for i = self.flushed_count + 1, #self.buffer do
        table.insert(new_lines, self.buffer[i])
    end

    local ok, _ = pcall(vim.fn.writefile, new_lines, self.filepath, "a")
    if not ok then return end
    self.flushed_count = #self.buffer
end

--- Reconfigure the logger with new settings
--- Updates enabled state and filepath. Sets up autocmds if enabling persistence.
--- Buffer contents are preserved — all pre-configure log lines carry forward.
---@param enabled boolean whether to persist logs to file
---@param log_filepath string? path to log file (keeps current if nil)
function Logger:configure(enabled, log_filepath)
    self.enabled = enabled or false
    if log_filepath then
        self.filepath = log_filepath
    end

    if self.enabled then
        self:_setup_autocmds()
    end
end

--- Get the internal log buffer
---@return string[] buffer log lines
function Logger:get_buffer()
    return self.buffer
end

--- Register autocmds for automatic buffer flushing
function Logger:_setup_autocmds()
    local group = vim.api.nvim_create_augroup("HuginnLogging", { clear = true })

    vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        callback = function()
            self:flush()
        end,
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            self:flush()
        end,
    })
end

return M
