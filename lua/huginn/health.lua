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

-- health.lua
-- :checkhealth huginn

local filepath = require("huginn.modules.filepath")
local config = require("huginn.modules.config")
local issue_index = require("huginn.modules.issue_index")
local time = require("huginn.modules.time")

local M = {}

--- Check Neovim version and core API availability
local function check_neovim()
    vim.health.start("Neovim environment")

    if vim.fn.has("nvim-0.9") == 1 then
        vim.health.ok("Neovim >= 0.9")
    else
        vim.health.error("Neovim >= 0.9 required", {
            "Huginn needs tree-sitter and extmark APIs introduced in 0.9",
        })
    end

    if vim.treesitter and vim.treesitter.get_parser then
        vim.health.ok("tree-sitter API available")
    else
        vim.health.error("tree-sitter API not found", {
            "Upgrade Neovim to a version with built-in tree-sitter support",
        })
    end
end

--- Check tree-sitter parser for the current buffer's filetype
local function check_treesitter_parser()
    vim.health.start("tree-sitter parsers")

    local bufnr = vim.api.nvim_get_current_buf()
    local ft = vim.bo[bufnr].filetype

    if not ft or ft == "" then
        vim.health.info("Current buffer has no filetype; skipping parser check")
        return
    end

    local lang = vim.treesitter.language.get_lang(ft) or ft
    local has_parser = pcall(vim.treesitter.language.inspect, lang)

    if has_parser then
        vim.health.ok("Parser installed for " .. ft)
    else
        vim.health.warn("No parser for " .. ft, {
            "Install with :TSInstall " .. lang,
            "Without a parser, issue locations cannot be resolved for this filetype",
        })
    end
end

--- Locate .huginn file and verify config loads
---@return string|nil cwd working directory
---@return table|nil cfg loaded configuration table
local function check_config()
    vim.health.start("Configuration")

    local cwd = vim.fn.getcwd()
    local huginn_path = filepath.find_huginn_file(cwd)
    if not huginn_path then
        vim.health.warn("No .huginn file found in directory tree", {
            "Run :HuginnInit to create one in the current directory",
        })
        return nil, nil
    end

    vim.health.ok(".huginn found: " .. huginn_path)

    local cfg, err = config.load(huginn_path)
    if err then
        vim.health.error("Failed to load config: " .. err, {
            "Check file for syntax errors: " .. huginn_path,
        })
        return nil, nil
    end

    vim.health.ok("Configuration loaded successfully")
    return cwd, cfg
end

--- Check whether an Issue.md file exists on disk for the given issue ID
---@param issue_dir string absolute path to issue directory
---@param issue_id string Huginn ID (yyyyMMdd_HHmmss)
---@return boolean
local function issue_exists_on_disk(issue_dir, issue_id)
    local parsed = time.parse_id(issue_id)
    if not parsed then return false end
    local year = string.format("%04d", parsed.year)
    local month = string.format("%02d", parsed.month)
    local path = filepath.join(issue_dir, year, month, issue_id, "Issue.md")
    return filepath.exists(path)
end

--- Check cache integrity: every indexed issue_id should map to an existing Issue.md
---@param cwd string working directory
---@param cfg table loaded configuration
local function check_cache_integrity(cwd, cfg)
    vim.health.start("Cache integrity")

    local issue_dir = filepath.join(cwd, cfg.plugin.issue_dir)
    local index_dir = filepath.join(issue_dir, ".index")

    if not filepath.exists(index_dir) then
        vim.health.ok("No index directory (nothing to check)")
        return
    end

    local results = issue_index.check_integrity(issue_dir, issue_exists_on_disk)

    if results.evicted == 0 then
        vim.health.ok("All " .. results.checked .. " cached entries map to existing issues")
    else
        local advice = {}
        for _, id in ipairs(results.evicted_ids) do
            table.insert(advice, "Evicted: " .. id)
        end
        vim.health.warn(
            "Evicted " .. results.evicted .. " stale entries (of " .. results.checked .. " checked)",
            advice
        )
    end
end

--- Check issue integrity: file existence and reference resolution
---@param cwd string working directory
---@param cfg table loaded configuration
local function check_issue_integrity(cwd, cfg)
    vim.health.start("Issue integrity")

    local doctor = require("huginn.modules.doctor")
    local scan_results, scan_err = doctor.scan(cwd, cfg)
    if scan_err then
        vim.health.error("Scan failed: " .. scan_err)
        return
    end

    if scan_results.total == 0 then
        vim.health.ok("No issues to check")
        return
    end

    for _, err_msg in ipairs(scan_results.errors) do
        vim.health.warn("Read error: " .. err_msg)
    end

    if #scan_results.missing_file > 0 then
        local advice = {}
        for _, item in ipairs(scan_results.missing_file) do
            table.insert(advice, item.issue_id .. " → " .. item.rel_filepath)
        end
        table.insert(advice, "Run :HuginnDoctor to relocate")
        vim.health.warn(#scan_results.missing_file .. " issue(s) reference missing files", advice)
    end

    if #scan_results.broken_refs > 0 then
        local advice = {}
        for _, item in ipairs(scan_results.broken_refs) do
            local refs = table.concat(item.broken_refs, ", ")
            table.insert(advice, item.issue_id .. " → " .. refs)
        end
        table.insert(advice, "Run :HuginnDoctor to repair")
        vim.health.warn(#scan_results.broken_refs .. " issue(s) have broken references", advice)
    end

    if #scan_results.missing_index > 0 then
        local advice = {}
        for _, item in ipairs(scan_results.missing_index) do
            table.insert(advice, item.issue_id)
        end
        table.insert(advice, "Run :HuginnDoctor to auto-repair")
        vim.health.warn(#scan_results.missing_index .. " issue(s) have missing index entries", advice)
    end

    local problem_count = #scan_results.missing_file
        + #scan_results.broken_refs + #scan_results.missing_index
    if problem_count == 0 then
        vim.health.ok("All " .. scan_results.total .. " issues healthy")
    end
end

function M.check()
    check_neovim()
    check_treesitter_parser()
    local cwd, cfg = check_config()
    if cwd and cfg then
        check_cache_integrity(cwd, cfg)
        check_issue_integrity(cwd, cfg)
    end
end

return M
