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

-- context.lua
-- Plugin context: singleton state container with durable and ephemeral portions


local config = require("huginn.modules.config")
local filepath = require("huginn.modules.filepath")

local M = {}

-- Registered config-change listeners (private)
---@type function[]
local listeners = {}

---@class huginn.Position
---@field line integer 1-based line number
---@field col integer 1-based column number
local Position = {}
Position.__index = Position

--- Create a new Position
---@param line integer 1-based line number
---@param col integer 1-based column number
---@return huginn.Position
function Position.new(line, col)
    local self = setmetatable({}, Position)
    self.line = line
    self.col = col
    return self
end

---@class huginn.WindowState
---@field filepath string absolute path to the source file (buffer name)
---@field mode string vim mode at invocation time ("n", "v", "V", "\22", etc.)
---@field start huginn.Position cursor position (normal) or selection start (visual)
---@field finish huginn.Position|nil selection end in visual mode, nil in normal mode
local WindowState = {}
WindowState.__index = WindowState

--- Create a new WindowState
---@param filepath string absolute path to the source file
---@param mode string vim mode string
---@param start huginn.Position cursor or selection start
---@param finish huginn.Position|nil selection end (nil for normal mode)
---@return huginn.WindowState
function WindowState.new(filepath, mode, start, finish)
    local self = setmetatable({}, WindowState)
    self.filepath = filepath
    self.mode = mode
    self.start = start
    self.finish = finish
    return self
end

---@class huginn.Context
---@field cwd string absolute path to the context root (directory containing .huginn)
---@field config table<string, table<string, any>> active configuration
---@field logger huginn.Logger
local Context = {}
Context.__index = Context

--- Create a new Context
---@param cwd string context root directory
---@param cfg table<string, table<string, any>> active configuration
---@param logger huginn.Logger plugin logger
---@return huginn.Context
function Context.new(cwd, cfg, logger)
    local self = setmetatable({}, Context)
    self.cwd = cwd
    self.config = cfg
    self.logger = logger
    return self
end

---@class huginn.CommandContext
---@field cwd string absolute path to the context root
---@field config table<string, table<string, any>> active configuration
---@field logger huginn.Logger plugin logger
---@field buffer integer neovim buffer number
---@field window huginn.WindowState|nil editor window state at command invocation
local CommandContext = {}
CommandContext.__index = CommandContext

--- Create a new CommandContext
---@param ctx huginn.Context the durable context
---@param bufnr integer neovim buffer number
---@param window_state huginn.WindowState|nil editor window state
---@return huginn.CommandContext
function CommandContext.new(ctx, bufnr, window_state)
    local self = setmetatable({}, CommandContext)
    self.cwd = ctx.cwd
    self.config = ctx.config
    self.logger = ctx.logger
    self.buffer = bufnr
    self.window = window_state
    return self
end

-- Singleton instance
---@type huginn.Context|nil
local instance = nil

--- Initialize the plugin context singleton
--- Discovers the nearest .huginn file, derives the context root, and loads configuration.
---@param start_path string? absolute path to begin .huginn search (defaults to vim.fn.getcwd())
---@param logger huginn.Logger bootstrapping logger
---@return huginn.Context|nil context the initialized context, or nil on error
---@return string|nil error error message if initialization failed
function M.init(start_path, logger)
    local search_from = start_path or vim.fn.getcwd()

    local huginn_path = filepath.find_huginn_file(search_from)
    if not huginn_path then
        return nil, "No .huginn file found"
    end

    local cwd = filepath.dirname(huginn_path)

    local cfg, err = config.load(huginn_path, logger)
    if not cfg then
        return nil, err
    end

    logger:configure(cfg.logging.enabled, filepath.relative_to_absolute(cfg.logging.filepath, cwd))

    instance = Context.new(cwd, cfg, logger)
    return instance, nil
end

--- Get the current plugin context singleton
---@return huginn.Context|nil context the current context, or nil if not initialized
function M.get()
    return instance
end

--- Create a command context for the given buffer
--- Bundles the durable singleton context with the ephemeral buffer reference
--- and optional editor window state.
---@param bufnr integer neovim buffer number
---@param window_state huginn.WindowState|nil editor window state at invocation
---@return huginn.CommandContext|nil context command context, or nil if not initialized
---@return string|nil error error message if context is not available
local function for_buffer(bufnr, window_state)
    if not instance then
        return nil, "Plugin context not initialized"
    end

    return CommandContext.new(instance, bufnr, window_state), nil
end

--- Register a callback to be called when configuration changes
---@param fn function callback receiving the new config table
function M.on_config_change(fn)
    table.insert(listeners, fn)
end

--- Register BufWritePost autocmd to reload config when .huginn file is saved
--- On reload, updates the singleton's config reference and notifies listeners.
---@param logger huginn.Logger? optional logger for reload warnings
function M.setup(logger)
    local group = vim.api.nvim_create_augroup("HuginnConfig", { clear = true })

    vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        pattern = "*",
        callback = function(args)
            if not config.huginn_path then
                return
            end
            local buf_path = filepath.normalize(vim.api.nvim_buf_get_name(args.buf))
            if buf_path ~= config.huginn_path then
                return
            end

            local cfg, err = config.reload(logger)
            if not cfg then
                if logger then
                    logger:alert("WARN", "Config reload failed: " .. (err or "unknown error"))
                end
                return
            end

            if instance then
                instance.config = cfg
            end

            for _, fn in ipairs(listeners) do
                fn(cfg)
            end
        end,
    })
end

--- Capture editor state and build a CommandContext from a user command invocation.
--- Reads the current buffer, constructs a WindowState from cursor position (normal)
--- or '</'> marks (visual), and delegates to for_buffer.
---@param opts table opts table from nvim_create_user_command callback
---@return huginn.CommandContext|nil context
---@return string|nil error
function M.from_command(opts)
    local bufnr = vim.api.nvim_get_current_buf()
    local buf_path = vim.api.nvim_buf_get_name(bufnr)

    local window_state
    if opts.range == 2 then
        local mode = vim.fn.visualmode()
        local start_line = vim.fn.line("'<")
        local start_col = vim.fn.col("'<")
        local finish_line = vim.fn.line("'>")
        local finish_col = vim.fn.col("'>")
        window_state = WindowState.new(
            buf_path,
            mode,
            Position.new(start_line, start_col),
            Position.new(finish_line, finish_col)
        )
    else
        local cursor = vim.api.nvim_win_get_cursor(0)
        window_state = WindowState.new(
            buf_path,
            "n",
            Position.new(cursor[1], cursor[2] + 1),
            nil
        )
    end

    return for_buffer(bufnr, window_state)
end

--- Reset the singleton instance (testing only)
function M._reset()
    instance = nil
    listeners = {}
end

M.Position = Position
M.WindowState = WindowState

return M
