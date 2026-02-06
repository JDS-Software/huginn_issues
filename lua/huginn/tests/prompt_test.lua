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

-- prompt_test.lua
-- Tests for the prompt input component

local M = {}

local prompt = require("huginn.components.prompt")

local function test_show_rejects_invalid_input()
    -- nil and non-function callbacks don't crash
    assert_true(pcall(prompt.show, "message", nil), "should not crash with nil callback")
    assert_true(pcall(prompt.show, "message", "not a function"), "should not crash with non-function callback")

    -- nil opts, empty message, missing message all yield nil
    local results = {}
    prompt.show(nil, function(input) results[1] = { called = true, input = input } end)
    prompt.show({ message = "" }, function(input) results[2] = { called = true, input = input } end)
    prompt.show({}, function(input) results[3] = { called = true, input = input } end)
    assert_true(results[1].called, "nil opts should call callback")
    assert_nil(results[1].input, "nil opts should yield nil")
    assert_true(results[2].called, "empty message should call callback")
    assert_nil(results[2].input, "empty message should yield nil")
    assert_true(results[3].called, "missing message should call callback")
    assert_nil(results[3].input, "missing message should yield nil")
end

local function test_show_opens_floating_window()
    local called = false
    local received = nil

    prompt.show("Test prompt", function(input)
        called = true
        received = input
    end)

    -- Window should be open with a buffer
    local wins = vim.api.nvim_list_wins()
    local found_float = false
    local float_win = nil
    local float_buf = nil
    for _, w in ipairs(wins) do
        local config = vim.api.nvim_win_get_config(w)
        if config.relative and config.relative ~= "" then
            found_float = true
            float_win = w
            float_buf = vim.api.nvim_win_get_buf(w)
            break
        end
    end

    assert_true(found_float, "should open a floating window")
    assert_not_nil(float_buf, "floating window should have a buffer")

    -- Buffer should be editable
    local modifiable = vim.api.nvim_get_option_value("modifiable", { buf = float_buf })
    assert_true(modifiable, "buffer should be modifiable")

    -- Filetype should be markdown
    local ft = vim.api.nvim_get_option_value("filetype", { buf = float_buf })
    assert_equal("markdown", ft, "filetype should be markdown")

    -- Clean up: close the window (triggers dismiss)
    vim.api.nvim_win_close(float_win, true)
    -- Process autocmds
    vim.cmd("doautocmd WinClosed")
end

local function test_show_string_shorthand()
    -- String opts should work the same as { message = str }
    local float_win = nil

    prompt.show("Shorthand test", function() end)

    local wins = vim.api.nvim_list_wins()
    for _, w in ipairs(wins) do
        local config = vim.api.nvim_win_get_config(w)
        if config.relative and config.relative ~= "" then
            float_win = w
            break
        end
    end

    assert_not_nil(float_win, "string shorthand should open a floating window")

    -- Check title contains the message
    local config = vim.api.nvim_win_get_config(float_win)
    -- title may be a string or table depending on Neovim version
    local title_str
    if type(config.title) == "string" then
        title_str = config.title
    elseif type(config.title) == "table" then
        local parts = {}
        for _, part in ipairs(config.title) do
            if type(part) == "table" then
                table.insert(parts, part[1])
            else
                table.insert(parts, part)
            end
        end
        title_str = table.concat(parts)
    end

    assert_not_nil(title_str, "window should have a title")
    assert_match("Shorthand test", title_str, "title should contain the prompt message")

    -- Clean up
    vim.api.nvim_win_close(float_win, true)
end

local function test_submit_returns_content()
    local received = nil

    prompt.show("Enter text", function(input)
        received = input
    end)

    -- Find the floating buffer
    local float_buf = nil
    local float_win = nil
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(w)
        if config.relative and config.relative ~= "" then
            float_win = w
            float_buf = vim.api.nvim_win_get_buf(w)
            break
        end
    end

    assert_not_nil(float_buf, "should have a floating buffer")

    -- Write content to the buffer
    vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, { "Line one", "Line two" })

    -- Simulate <C-s> by executing the buffer-local keymap
    vim.api.nvim_set_current_win(float_win)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-s>", true, false, true), "x", false)

    assert_equal("Line one\nLine two", received, "submit should return buffer content")
end

local function test_empty_submit_returns_empty_string()
    local received = "sentinel"

    prompt.show("Enter text", function(input)
        received = input
    end)

    -- Find the floating window
    local float_win = nil
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(w)
        if config.relative and config.relative ~= "" then
            float_win = w
            break
        end
    end

    assert_not_nil(float_win, "should have a floating window")

    -- Submit without typing anything
    vim.api.nvim_set_current_win(float_win)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-s>", true, false, true), "x", false)

    assert_equal("", received, "empty submit should return empty string")
end

local function test_dismiss_returns_nil()
    local received = "sentinel"

    prompt.show("Enter text", function(input)
        received = input
    end)

    -- Find the floating window
    local float_win = nil
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(w)
        if config.relative and config.relative ~= "" then
            float_win = w
            break
        end
    end

    assert_not_nil(float_win, "should have a floating window")

    -- Dismiss with Esc
    vim.api.nvim_set_current_win(float_win)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)

    assert_nil(received, "dismiss should return nil")
end

local function test_default_content_prefills_buffer()
    prompt.show({ message = "Edit text", default = "prefilled\ncontent" }, function() end)

    -- Find the floating buffer
    local float_buf = nil
    local float_win = nil
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(w)
        if config.relative and config.relative ~= "" then
            float_win = w
            float_buf = vim.api.nvim_win_get_buf(w)
            break
        end
    end

    assert_not_nil(float_buf, "should have a floating buffer")

    local lines = vim.api.nvim_buf_get_lines(float_buf, 0, -1, false)
    assert_equal(2, #lines, "should have two lines of default content")
    assert_equal("prefilled", lines[1], "first line should be 'prefilled'")
    assert_equal("content", lines[2], "second line should be 'content'")

    -- Clean up
    vim.api.nvim_win_close(float_win, true)
end

function M.run()
    local runner = TestRunner.new("prompt")

    runner:test("show rejects invalid input gracefully", test_show_rejects_invalid_input)
    runner:test("show opens a floating window with editable buffer", test_show_opens_floating_window)
    runner:test("show accepts string shorthand with title", test_show_string_shorthand)
    runner:test("submit returns buffer content", test_submit_returns_content)
    runner:test("empty submit returns empty string", test_empty_submit_returns_empty_string)
    runner:test("dismiss returns nil", test_dismiss_returns_nil)
    runner:test("default content pre-fills the buffer", test_default_content_prefills_buffer)

    runner:run()
end

return M
