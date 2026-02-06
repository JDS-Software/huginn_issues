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

-- doctor.lua
-- HuginnDoctor command: scan issue integrity and interactively repair problems

local context = require("huginn.modules.context")
local doctor = require("huginn.modules.doctor")

local M = {}

--- Execute the HuginnDoctor command
---@param opts table opts table from nvim_create_user_command callback
---@return string|nil error error message if the command failed
function M.execute(opts)
    local cmd_ctx, ctx_err = context.from_command(opts)
    if not cmd_ctx then
        return ctx_err
    end

    local scan_results, scan_err = doctor.scan(cmd_ctx.cwd, cmd_ctx.config)
    if scan_err then
        return scan_err
    end

    local problem_count = #scan_results.missing_file
        + #scan_results.broken_refs + #scan_results.missing_index

    if problem_count == 0 then
        cmd_ctx.logger:alert("INFO", "All " .. scan_results.total .. " issues healthy")
        return nil
    end

    cmd_ctx.logger:alert("INFO", "Found " .. problem_count .. " problem(s)")
    doctor.repair(cmd_ctx, scan_results)
    return nil
end

return M
