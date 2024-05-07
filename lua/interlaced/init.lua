#!/usr/bin/env lua

local keyset = vim.keymap.set
local setline = vim.fn.setline
local getline = vim.fn.getline
local vim_fn = vim.fn
local vim_api = vim.api
local vim_cmd = vim.cmd
local vim_schedule = vim.schedule
local create_command = vim_api.nvim_create_user_command

local config = require("interlaced.config")
local _H = {}
local M = {
  _H = _H,
  _Name = "Interlaced",
  _orig_mappings = {},
  config = {},
  cmd = {},
}
local user_conf = {}

---@param msg string # message to log
---@param kind string # hl group to use for logging
---@param history boolean # whether to add the message to history
M._log = function(msg, kind, history)
  vim_schedule(function()
    vim_api.nvim_echo({
      { M._Name .. ": " .. msg, kind },
    }, history, {})
  end)
end

-- nicer error messages using nvim_echo
---@param msg string # error message
M.error = function(msg)
  M._log(msg, "ErrorMsg", true)
end

-- nicer warning messages using nvim_echo
---@param msg string # warning message
M.warning = function(msg)
  M._log(msg, "WarningMsg", true)
end

-- nicer plain messages using nvim_echo
---@param msg string # plain message
M.info = function(msg)
  M._log(msg, "Normal", true)
end

_H.append_to_3_lines_above = function(lineno)
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

_H.delete_trailing_empty_lines = function()
  local last_lineno = vim_fn.line("$")
  local buf = vim_api.nvim_get_current_buf()
  while getline(last_lineno):match("^%s*$") do
    vim_fn.deletebufline(buf, last_lineno)
    last_lineno = last_lineno - 1
  end
end

M.cmd.MapInterlaced = function()
  for func, shortcut in pairs(M.config.mappings) do
    _H.store_orig_mapping(shortcut)
    keyset("n", shortcut, M.cmd[func], { noremap = true, buffer = true, nowait = true })
  end
end

M.cmd.UnmapInterlaced = function()
  for keystroke, mapping in pairs(M._orig_mappings) do
    if vim.tbl_isempty(mapping) then
      vim_api.nvim_buf_del_keymap(0, "n", keystroke)
    else
      mapping.buffer = true
      vim_fn.mapset("n", false, mapping)
    end
  end
end

M.cmd.JoinUp = function()
  local lineno = vim_fn.line(".")
  if lineno <= 3 then
    M.warning("Joining too early, please move down your cursor.")
    return
  end

  _H.append_to_3_lines_above(lineno)

  lineno = lineno + 3
  local last_lineno = vim_fn.line("$")
  while lineno <= last_lineno do
    setline(lineno - 3, getline(lineno))
    lineno = lineno + 3
  end
  setline(lineno - 3, "")

  _H.delete_trailing_empty_lines()
  vim_cmd("w")
end

M.cmd.JoinUpPair = function()
  local here = vim_fn.getpos(".")
  vim_cmd([[normal! {]])
  for _ = 1, 2 do
    vim_fn.setcursorcharpos({ vim_fn.line(".") + 1, 1 })
    M.cmd.JoinUp()
  end
  vim_fn.setpos(".", here)
end

M.cmd.PullUp = function()
  local here = vim_fn.getpos(".")
  local curr_lineno = here[2]
  local last_lineno = vim_fn.line("$")
  if last_lineno - curr_lineno < 3 then
    M.warning("No more lines can be pulled up.")
    return
  end

  vim_fn.setcursorcharpos({ curr_lineno + 3, 1 })
  M.cmd.JoinUp()
  vim_fn.setpos(".", here)
end

M.cmd.PullUpPair = function()
  local here = vim_fn.getpos(".")
  local curr_lineno = here[2]
  local last_lineno = vim_fn.line("$")
  if last_lineno - curr_lineno < 3 + 1 then
    M.warning("No more lines can be pulled up.")
    return
  end

  vim_cmd([[normal! }]])
  for _ = 1, 2 do
    vim_fn.setcursorcharpos({ vim_fn.line(".") + 1, 1 })
    M.cmd.JoinUp()
  end
  vim_fn.setpos(".", here)
end

M.cmd.SplitAtCursor = function()
  local lineno = vim_fn.line(".")
  local last_lineno = vim_fn.line("$")

  vim_fn.append(last_lineno, { "", "", "" })

  local last_counterpart_lineno = last_lineno
  while (last_counterpart_lineno - lineno) % 3 ~= 0 do
    last_counterpart_lineno = last_counterpart_lineno - 1
  end

  for i = last_counterpart_lineno, lineno + 3, -3 do
    setline(i + 3, getline(i))
  end

  local current_line = getline(lineno)
  local cursor_col = vim_fn.col(".")

  local before_cursor = current_line:sub(1, cursor_col - 1)
  local after_cursor = current_line:sub(cursor_col)

  setline(lineno, vim_fn.substitute(before_cursor, [[\s\+$]], "", ""))
  setline(lineno + 3, vim_fn.substitute(after_cursor, [[^\s\+]], "", ""))

  _H.delete_trailing_empty_lines()
  vim_cmd("w")
end

M.cmd.JoinDown = function()
  vim_cmd([[normal! 0]])
  M.cmd.SplitAtCursor()
end

M.cmd.NavigateDown = function()
  vim_cmd([[normal! 03j]])
end

M.cmd.NavigateUp = function()
  vim_cmd([[normal! 03k]])
end

_H.InterlacedSplitHelper = function(regex)
  -- cmd([[saveas! %.splitted]])
  local buf = vim_api.nvim_get_current_buf()
  local last_lineno = vim_fn.line("$")
  for i = last_lineno, 1, -1 do
    line = getline(i)
    local sents = vim_fn.split(line, regex)

    vim_fn.deletebufline(buf, i)
    vim_fn.append(i - 1, sents)
  end
  vim_cmd([[w]])
end

M.cmd.SplitChineseSentences = function()
  -- :h split()
  -- Use '\zs' at the end of the pattern to keep the separator.
  -- :echo split('bar:foo', ':\zs')
  local regex = [[\v[…。!！?？—]+[’”"]?\zs]]
  _H.InterlacedSplitHelper(regex)
end

M.cmd.SplitEnglishSentences = function()
  local regex = [[\v(%(%(\u\l{,2})@<!(\.\a)@<!\.|[!?])+['’"”]?)%(\s|$)\zs]]
  _H.InterlacedSplitHelper(regex)
end

_H.store_orig_mapping = function(shortcut)
  mapping = vim_fn.maparg(shortcut, "n", false, true)
  M._orig_mappings[shortcut] = mapping
end

M.setup = function(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    M.error(string.format("setup() expects table, but got %s:\n%s", type(opts), vim.inspect(opts)))
    opts = {}
  end
  M.config = vim.tbl_deep_extend("force", config, opts)

  if M.config.setup_mappings_now then
    M.cmd.MapInterlaced()
  end

  for cmd, func in pairs(M.cmd) do
    create_command(cmd, func, {})
  end
end

return M
