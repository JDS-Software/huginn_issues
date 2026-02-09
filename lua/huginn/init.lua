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

-- init.lua
-- Command dispatcher, setup function, register commands

local logging = require("huginn.modules.logging")
local context = require("huginn.modules.context")
local issue_index = require("huginn.modules.issue_index")
local annotation = require("huginn.modules.annotation")
local huginn_init = require("huginn.commands.huginn_init")
local huginn_config = require("huginn.commands.config")
local huginn_log = require("huginn.commands.log")
local huginn_create = require("huginn.commands.create")
local huginn_show = require("huginn.commands.show")
local huginn_navigate = require("huginn.commands.navigate")
local huginn_add_remove = require("huginn.commands.add_and_remove")
local huginn_home = require("huginn.commands.home")
local huginn_doctor = require("huginn.commands.doctor")

local M = {}

local logger

local default_keymaps = {
    create = "<leader>hc",
    show = "<leader>hs",
    next = "<leader>hn",
    previous = "<leader>hp",
    add = "<leader>ha",
    remove = "<leader>hr",
    home = "<leader>hh",
}

--- Register all user commands
local function register_commands()
    vim.api.nvim_create_user_command("HuginnInit", function()
        huginn_init.execute(logger)
    end, {
        desc = "Initialize a .huginn configuration file",
    })

    vim.api.nvim_create_user_command("HuginnConfig", function()
        local err = huginn_config.execute()
        if err then
            logger:alert("WARN", err)
        end
    end, {
        desc = "Open the .huginn configuration file",
    })

    vim.api.nvim_create_user_command("HuginnLog", function()
        huginn_log.execute(logger)
    end, {
        desc = "Show the Huginn log buffer in a floating window",
    })

    vim.api.nvim_create_user_command("HuginnCreate", function(opts)
        local err = huginn_create.execute(opts)
        if err then
            logger:alert("WARN", err)
        end
    end, {
        desc = "Create a new Huginn issue at the current location",
        range = true,
    })

    vim.api.nvim_create_user_command("HuginnShow", function(opts)
        local err = huginn_show.execute(opts)
        if err then
            logger:alert("WARN", err)
        end
    end, {
        desc = "Show issues for the current buffer",
    })

    vim.api.nvim_create_user_command("HuginnAdd", function(opts)
        local err = huginn_add_remove.execute_add(opts)
        if err then
            logger:alert("WARN", err)
        end
    end, {
        desc = "Add a tree-sitter scope reference to an existing issue",
    })

    vim.api.nvim_create_user_command("HuginnRemove", function(opts)
        local err = huginn_add_remove.execute_remove(opts)
        if err then
            logger:alert("WARN", err)
        end
    end, {
        desc = "Remove a tree-sitter scope reference from an existing issue",
    })

    vim.api.nvim_create_user_command("HuginnNext", function(opts)
        local err = huginn_navigate.execute_next(opts)
        if err then
            logger:alert("WARN", err)
        end
    end, {
        desc = "Jump to the next issue location in the current buffer",
    })

    vim.api.nvim_create_user_command("HuginnPrevious", function(opts)
        local err = huginn_navigate.execute_previous(opts)
        if err then
            logger:alert("WARN", err)
        end
    end, {
        desc = "Jump to the previous issue location in the current buffer",
    })

    vim.api.nvim_create_user_command("HuginnHome", function(opts)
        local err = huginn_home.execute(opts)
        if err then
            logger:alert("WARN", err)
        end
    end, {
        desc = "Show all project files with issues",
    })

    vim.api.nvim_create_user_command("HuginnDoctor", function(opts)
        local err = huginn_doctor.execute(opts)
        if err then
            logger:alert("WARN", err)
        end
    end, {
        desc = "Check issue integrity and interactively repair problems",
    })
end

--- register all user keymaps
local function register_keymap(keymaps)
    -- Register keymaps (only when plugin is active)
    if keymaps.create then
        vim.keymap.set({ "n", "v" }, keymaps.create, ":HuginnCreate<CR>",
            { silent = true, desc = "Create Huginn issue" })
    end

    if keymaps.show then
        vim.keymap.set("n", keymaps.show, ":HuginnShow<CR>",
            { silent = true, desc = "Show Huginn issues for current buffer" })
    end

    if keymaps.next then
        vim.keymap.set("n", keymaps.next, ":HuginnNext<CR>",
            { silent = true, desc = "Jump to next Huginn issue location" })
    end

    if keymaps.previous then
        vim.keymap.set("n", keymaps.previous, ":HuginnPrevious<CR>",
            { silent = true, desc = "Jump to previous Huginn issue location" })
    end

    if keymaps.add then
        vim.keymap.set("n", keymaps.add, ":HuginnAdd<CR>",
            { silent = true, desc = "Add scope reference to Huginn issue" })
    end

    if keymaps.remove then
        vim.keymap.set("n", keymaps.remove, ":HuginnRemove<CR>",
            { silent = true, desc = "Remove scope reference from Huginn issue" })
    end

    if keymaps.home then
        vim.keymap.set("n", keymaps.home, ":HuginnHome<CR>",
            { silent = true, desc = "Show all project files with issues" })
    end
end

--- Setup function
---@param opts table? plugin options
function M.setup(opts)
    if vim.g.loaded_huginn then
        return
    end

    opts = opts or {}

    logger = logging.new(false, ".huginnlog")

    context.setup(logger)
    issue_index.setup()
    annotation.setup()

    register_commands()
    -- Merge keymap overrides: user values replace defaults, false disables
    local keymaps = vim.tbl_extend("force", default_keymaps, opts.keymaps or {})
    register_keymap(keymaps)

    local ctx, err = context.init(nil, logger)

    if not ctx then
        logger:log("INFO", "Huginn dormant: " .. (err or "unknown error"))
        return
    end
    logger:log("INFO", "Huginn initialized: " .. ctx.cwd)

    vim.g.loaded_huginn = true
end

return M
