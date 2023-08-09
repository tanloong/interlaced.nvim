#!/usr/bin/env lua
local keymap = vim.keymap.set
local setline = vim.fn.setline
local getline = vim.fn.getline
local fn = vim.fn

local function append_to_3_lines_above(lineno)
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

local function delete_trailing_empty_lines()
    local last_lineno = fn.line("$")
    local buf = vim.api.nvim_get_current_buf()
    while string.match(getline(last_lineno), "^%s*$") do
        fn.deletebufline(buf, last_lineno)
        last_lineno = last_lineno - 1
    end
end

local function move_line_up()
    local lineno = fn.line(".")
    if lineno <= 3 then return end

    append_to_3_lines_above(lineno)

    lineno = lineno + 3
    local last_lineno = fn.line("$")
    while lineno <= last_lineno do
        setline(lineno - 3, getline(lineno))
        lineno = lineno + 3
    end
    setline(lineno - 3, "")

    delete_trailing_empty_lines()
    vim.cmd("w")
end

local function split_after_cursor()
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

    delete_trailing_empty_lines()
    vim.cmd("w")
end

local function move_line_down()
    vim.cmd([[normal! 0]])
    split_after_cursor()
end

local function setup()
    local mappings = {
        { mode = "n", from = ",", to = move_line_up },
        { mode = "n", from = "d", to = split_after_cursor },
        { mode = "n", from = "D", to = move_line_down },
        { mode = "n", from = "K", to = "3k" },
        { mode = "n", from = "J", to = "3j" }
    }
    for _, mapping in ipairs(mappings) do
        keymap(mapping.mode, mapping.from, mapping.to, { buffer = true, nowait = true })
    end
end

return { setup = setup }
