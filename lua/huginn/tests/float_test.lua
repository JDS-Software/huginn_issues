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

-- float_test.lua
-- Tests for shared floating window utilities

local M = {}

local float = require("huginn.components.float")

local function test_make_win_opts_fixed_and_dynamic()
    -- Fixed height mode
    local fixed = float.make_win_opts({ width_ratio = 0.6, height_ratio = 0.3, title = "Test" })
    assert_equal("editor", fixed.relative)
    assert_equal(" Test ", fixed.title)
    assert_equal("center", fixed.title_pos)
    assert_equal("rounded", fixed.border)
    assert_equal(math.floor(vim.o.columns * 0.6), fixed.width)
    assert_equal(math.floor(vim.o.lines * 0.3), fixed.height)
    assert_nil(fixed.footer, "footer should be nil when not provided")

    -- Dynamic height mode
    local dynamic = float.make_win_opts({
        width_ratio = 0.8,
        height_ratio = 0.5,
        title = "Dynamic",
        content_count = 5,
        content_offset = 4,
    })
    local max_h = math.floor(vim.o.lines * 0.5)
    assert_equal(math.min(5 + 4, max_h), dynamic.height)

    -- Dynamic with content_count=0 -> treated as 1
    local empty = float.make_win_opts({
        width_ratio = 0.8,
        height_ratio = 0.5,
        title = "Empty",
        content_count = 0,
        content_offset = 4,
    })
    assert_equal(math.min(1 + 4, max_h), empty.height)

    -- Footer pass-through
    local footer = { { " help ", "Comment" } }
    local with_footer = float.make_win_opts({
        width_ratio = 0.6,
        height_ratio = 0.7,
        title = "Footer",
        footer = footer,
        footer_pos = "center",
    })
    assert_equal(footer, with_footer.footer)
    assert_equal("center", with_footer.footer_pos)
end

local function test_create_buf()
    local buf = float.create_buf("markdown")
    assert_true(vim.api.nvim_buf_is_valid(buf))
    assert_equal("nofile", vim.api.nvim_get_option_value("buftype", { buf = buf }))
    assert_equal("wipe", vim.api.nvim_get_option_value("bufhidden", { buf = buf }))
    assert_false(vim.api.nvim_get_option_value("swapfile", { buf = buf }))
    assert_equal("markdown", vim.api.nvim_get_option_value("filetype", { buf = buf }))
    vim.api.nvim_buf_delete(buf, { force = true })

    local buf2 = float.create_buf()
    assert_equal("", vim.api.nvim_get_option_value("filetype", { buf = buf2 }))
    vim.api.nvim_buf_delete(buf2, { force = true })
end

local function test_on_win_closed_fires_cleanup()
    local cleaned = false
    local group = vim.api.nvim_create_augroup("FloatTestWinClosed", { clear = true })
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor", width = 10, height = 5, row = 1, col = 1,
    })

    float.on_win_closed(group, win, "FloatTestWinClosed", function()
        cleaned = true
    end)

    vim.api.nvim_win_close(win, true)
    assert_true(cleaned, "cleanup_fn should have been called")
end

function M.run()
    local runner = TestRunner.new("float")

    runner:test("make_win_opts() fixed and dynamic height modes", test_make_win_opts_fixed_and_dynamic)
    runner:test("create_buf() sets standard buffer options", test_create_buf)
    runner:test("on_win_closed() fires cleanup on close", test_on_win_closed_fires_cleanup)

    runner:run()
end

return M
