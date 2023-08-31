#!/usr/bin/env lua
local keymap = vim.keymap.set
local setline = vim.fn.setline
local getline = vim.fn.getline
local fn = vim.fn
local api = vim.api

local utils = {}
function utils.append_to_3_lines_above(lineno)
    local lineno_minus3 = lineno - 3
    local lineno_minus1 = lineno - 1
    local line = getline(lineno)
    local line_minus3 = getline(lineno_minus3)
    local line_minus1 = getline(lineno_minus1)

    local sep = " "
    if line_minus1 == "" or line_minus3 == "" then sep = "" end
    setline(lineno_minus3, line_minus3:gsub("%s+$", "") .. sep .. line)
    setline(lineno, "")
end

function utils.delete_trailing_empty_lines()
    local last_lineno = fn.line("$")
    local buf = api.nvim_get_current_buf()
    while string.match(getline(last_lineno), "^%s*$") do
        fn.deletebufline(buf, last_lineno)
        last_lineno = last_lineno - 1
    end
end

function utils.InterlacedJoinUp()
    local lineno = fn.line(".")
    if lineno <= 3 then
        print("[interlaced.nvim] Joining too early, please move down your cursor.")
        return
    end

    utils.append_to_3_lines_above(lineno)

    lineno = lineno + 3
    local last_lineno = fn.line("$")
    while lineno <= last_lineno do
        setline(lineno - 3, getline(lineno))
        lineno = lineno + 3
    end
    setline(lineno - 3, "")

    utils.delete_trailing_empty_lines()
    vim.cmd("w")
end

function utils.InterlacedSplitDownAtCursor()
    local lineno = fn.line(".")
    local last_lineno = fn.line("$")

    fn.append(last_lineno, { "", "", "" })

    local last_counterpart_lineno = last_lineno
    while (last_counterpart_lineno - lineno) % 3 ~= 0 do
        last_counterpart_lineno = last_counterpart_lineno - 1
    end

    for i = last_counterpart_lineno, lineno + 3, -3 do
        setline(i + 3, getline(i))
    end

    local current_line = getline(lineno)
    local cursor_col = fn.col(".")

    local before_cursor = current_line:sub(1, cursor_col - 1)
    local after_cursor = current_line:sub(cursor_col)

    setline(lineno, fn.substitute(before_cursor, [[\s\+$]], "", ""))
    setline(lineno + 3, fn.substitute(after_cursor, [[^\s\+]], "", ""))

    utils.delete_trailing_empty_lines()
    vim.cmd("w")
end

function utils.InterlacedJoinDown()
    vim.cmd([[normal! 0]])
    utils.InterlacedSplitDownAtCursor()
end

function utils.InterlacedNavDown()
    vim.cmd([[normal! 03j]])
end

function utils.InterlacedNavUp()
    vim.cmd([[normal! 03k]])
end

local function setup_global_mappings(user_conf)
    local config = {
        InterlacedJoinUp = ",",
        InterlacedSplitDownAtCursor = "d",
        InterlacedJoinDown = "D",
        InterlacedNavDown = "J",
        InterlacedNavUp = "K"
    }
    config = vim.tbl_deep_extend("force", config, user_conf)

    for func, keystroke in pairs(config) do
        keymap("n", keystroke, utils[func], { noremap = true, buffer = true, nowait = true })
    end
end

local function setup_commands()
    local command = api.nvim_create_user_command
    command("InterlacedJoinUp", utils.InterlacedJoinUp, {})
    command("InterlacedSplitDownAtCursor", utils.InterlacedSplitDownAtCursor, {})
    command("InterlacedJoinDown", utils.InterlacedJoinDown, {})
    command("InterlacedNavDown", utils.InterlacedNavDown, {})
    command("InterlacedNavUp", utils.InterlacedNavUp, {})
end

local function setup(user_conf)
    user_conf = user_conf or {}
    setup_global_mappings(user_conf)
    setup_commands()
end

return {
    setup = setup
}
